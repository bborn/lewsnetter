class Account::TeamVariablesController < Account::ApplicationController
  # GET /account/teams/:team_id/variables.json
  #
  # Returns the list of interpolation variables available to campaigns on this
  # team — built-ins ({first_name, last_name, email, external_id,
  # unsubscribe_url}) plus any custom_attribute keys observed across the team's
  # subscribers. Used by the variable_picker Stimulus controller on the
  # campaign edit page.
  #
  # Sample values come from the first subscriber that has a non-empty value
  # for that key. Built-in samples come from any subscriber that has the
  # field; nil if none.
  def index
    @team = current_user.teams.find(params[:team_id])
    authorize! :read, @team

    sample_sub = @team.subscribers.first

    built_ins = [
      {name: "first_name", category: "built-in", sample: built_in_sample(sample_sub, :first_name)},
      {name: "last_name", category: "built-in", sample: built_in_sample(sample_sub, :last_name)},
      {name: "email", category: "built-in", sample: sample_sub&.email},
      {name: "external_id", category: "built-in", sample: sample_sub&.external_id},
      {name: "unsubscribe_url", category: "built-in", sample: nil}
    ]

    custom = custom_variables(@team)

    render json: built_ins + custom
  end

  private

  def built_in_sample(subscriber, kind)
    return nil unless subscriber
    case kind
    when :first_name
      subscriber.name.to_s.strip.split(/\s+/, 2).first
    when :last_name
      _first, last = subscriber.name.to_s.strip.split(/\s+/, 2)
      last
    end
  end

  # Distinct custom_attribute keys across the team's subscribers (capped at 500
  # rows so this stays O(1) regardless of audience size). For each key, returns
  # the first non-empty sample value we see.
  def custom_variables(team)
    samples = {} # key => first non-empty value

    team.subscribers
      .where.not(custom_attributes: {})
      .limit(500)
      .pluck(:custom_attributes)
      .each do |attrs|
        next unless attrs.is_a?(Hash)
        attrs.each do |k, v|
          next if k.to_s.strip.empty?
          # First non-empty value wins; don't overwrite an already-found sample.
          if !samples.key?(k) || (samples[k].to_s.strip.empty? && !v.to_s.strip.empty?)
            samples[k] = v
          end
        end
      end

    samples.keys.sort.map do |k|
      {name: k.to_s, category: "custom", sample: samples[k]}
    end
  end
end
