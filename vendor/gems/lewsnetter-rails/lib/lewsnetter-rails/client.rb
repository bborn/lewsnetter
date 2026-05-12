require "net/http"
require "uri"
require "json"
require "digest"
require "securerandom"
require "time"

module Lewsnetter
  # Net::HTTP-based JSON client for the Lewsnetter API. No Faraday.
  #
  # Raises:
  #   Lewsnetter::AuthenticationError (401/403)
  #   Lewsnetter::RateLimitedError    (429)
  #   Lewsnetter::ApiError            (other 4xx/5xx, network errors)
  class Client
    USER_AGENT = "lewsnetter-rails/#{Lewsnetter::VERSION}".freeze

    attr_reader :configuration

    def initialize(configuration = Lewsnetter.configuration)
      @configuration = configuration
    end

    # Upsert a single subscriber.
    #
    # Required: :external_id
    # Optional: :email, :name, :subscribed, :attributes
    def upsert_subscriber(external_id:, email: nil, name: nil, subscribed: true, attributes: nil)
      payload = {
        subscriber: compact({
          external_id: external_id.to_s,
          email: email,
          name: name,
          subscribed: subscribed,
          attributes: attributes
        })
      }
      post_json(configuration.subscribers_url, payload, idempotency_seed: external_id.to_s)
    end

    # Track a behavioral event.
    def track_event(external_id:, event:, properties: nil, occurred_at: nil)
      occurred_at ||= Time.now.utc.iso8601
      payload = compact({
        external_id: external_id.to_s,
        event: event.to_s,
        occurred_at: occurred_at.is_a?(Time) ? occurred_at.utc.iso8601 : occurred_at,
        properties: properties
      })
      post_json(configuration.events_track_url, payload, idempotency_seed: "#{external_id}:#{event}:#{occurred_at}")
    end

    # Bulk upsert subscribers. `rows` is an array of subscriber hashes.
    # Streams as NDJSON. Returns the parsed response body hash.
    def bulk_upsert_subscribers(rows)
      ndjson = rows.map { |row| JSON.dump(row) }.join("\n")
      post_ndjson(configuration.subscribers_bulk_url, ndjson)
    end

    # Bulk track events. `rows` is an array of event hashes.
    def bulk_track_events(rows)
      ndjson = rows.map { |row| JSON.dump(row) }.join("\n")
      post_ndjson(configuration.events_bulk_url, ndjson)
    end

    # Delete a subscriber by external_id (GDPR-style hard delete).
    def delete_subscriber(external_id)
      url = configuration.subscriber_by_external_id_url(external_id)
      uri = URI.parse(url)
      request = Net::HTTP::Delete.new(uri.request_uri)
      apply_common_headers!(request, idempotency_seed: "delete:#{external_id}")
      perform(uri, request)
    end

    private

    def post_json(url, payload, idempotency_seed:)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      body = JSON.dump(payload)
      request.body = body
      request["Content-Type"] = "application/json"
      apply_common_headers!(request, idempotency_seed: "#{idempotency_seed}:#{Digest::SHA256.hexdigest(body)}")
      perform(uri, request)
    end

    def post_ndjson(url, ndjson_body)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = ndjson_body
      request["Content-Type"] = "application/x-ndjson"
      apply_common_headers!(request, idempotency_seed: Digest::SHA256.hexdigest(ndjson_body))
      perform(uri, request)
    end

    def apply_common_headers!(request, idempotency_seed:)
      configuration.validate!
      request["Authorization"] = "Bearer #{configuration.api_key}"
      request["Accept"] = "application/json"
      request["User-Agent"] = USER_AGENT
      request["Idempotency-Key"] = Digest::SHA256.hexdigest(idempotency_seed.to_s)
    end

    def perform(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = configuration.http_open_timeout
      http.read_timeout = configuration.http_read_timeout

      response = begin
        http.request(request)
      rescue Timeout::Error, IOError, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
        raise Lewsnetter::ApiError.new("network error: #{e.class}: #{e.message}", status: nil)
      end

      handle_response(response)
    end

    def handle_response(response)
      code = response.code.to_i
      body_str = response.body.to_s

      case code
      when 200..299
        parse_body(body_str)
      when 401, 403
        raise Lewsnetter::AuthenticationError.new(body_str, status: code)
      when 429
        retry_after = response["Retry-After"]
        raise Lewsnetter::RateLimitedError.new("rate limited", status: code, retry_after: retry_after)
      when 400..499
        raise Lewsnetter::ApiError.new("client error #{code}: #{body_str}", status: code)
      when 500..599
        raise Lewsnetter::ApiError.new("server error #{code}: #{body_str}", status: code)
      else
        raise Lewsnetter::ApiError.new("unexpected status #{code}: #{body_str}", status: code)
      end
    end

    def parse_body(body_str)
      return {} if body_str.nil? || body_str.empty?
      JSON.parse(body_str)
    rescue JSON::ParserError
      {"raw" => body_str}
    end

    def compact(hash)
      hash.reject { |_, v| v.nil? }
    end
  end
end
