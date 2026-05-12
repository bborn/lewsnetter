module Lewsnetter
  # Helpers callable on the Lewsnetter module.
  module Tracker
    # Lewsnetter.track(user, "report_viewed", report_id: 42)
    #
    # `record` may be:
    #   - an object that responds to `lewsnetter_payload` (acts_as_lewsnetter_subscriber)
    #   - any object that responds to the configured external_id method
    #   - a String/Integer external_id directly
    def track(record, event_name, properties = {})
      external_id = extract_external_id(record)
      payload = {
        external_id: external_id.to_s,
        event: event_name.to_s,
        occurred_at: Time.now.utc.iso8601,
        properties: properties.to_h
      }

      if Lewsnetter.configuration.async
        Lewsnetter::TrackJob.perform_later(payload)
      else
        Lewsnetter::TrackJob.new.perform(payload)
      end
    end

    private

    def extract_external_id(record)
      return record if record.is_a?(String) || record.is_a?(Integer)
      if record.respond_to?(:lewsnetter_payload)
        record.lewsnetter_payload[:external_id]
      elsif record.respond_to?(:id)
        record.id
      else
        raise ArgumentError, "Cannot derive external_id from #{record.inspect}"
      end
    end
  end
end
