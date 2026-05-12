module Lewsnetter
  # Configuration container. Set via `Lewsnetter.configure { |c| ... }`.
  class Configuration
    attr_accessor :api_key,
      :team_id,
      :endpoint,
      :default_attributes_proc,
      :logger,
      :async,
      :http_open_timeout,
      :http_read_timeout

    def initialize
      @api_key = nil
      @team_id = nil
      @endpoint = "https://app.lewsnetter.com/api/v1"
      @default_attributes_proc = nil
      @logger = nil
      @async = true
      @http_open_timeout = 5
      @http_read_timeout = 15
    end

    # Returns the team-scoped subscribers collection URL.
    def subscribers_url
      "#{endpoint}/teams/#{team_id}/subscribers"
    end

    def subscribers_bulk_url
      "#{endpoint}/teams/#{team_id}/subscribers/bulk"
    end

    def events_track_url
      "#{endpoint}/teams/#{team_id}/events/track"
    end

    def events_bulk_url
      "#{endpoint}/teams/#{team_id}/events/bulk"
    end

    def subscriber_by_external_id_url(external_id)
      "#{endpoint}/teams/#{team_id}/subscribers/by_external_id/#{external_id}"
    end

    def validate!
      raise Lewsnetter::ConfigurationError, "api_key is required" if api_key.nil? || api_key.to_s.empty?
      raise Lewsnetter::ConfigurationError, "team_id is required" if team_id.nil?
      raise Lewsnetter::ConfigurationError, "endpoint is required" if endpoint.nil? || endpoint.to_s.empty?
      true
    end
  end
end
