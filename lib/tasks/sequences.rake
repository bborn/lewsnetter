namespace :sequences do
  # Port Intercom Series into draft Sequences. Nothing sends: every sequence
  # is created as a draft for review.
  #
  #   bin/rails sequences:import_intercom_series TEAM_ID=1 \
  #     EXPORT_DIR=~/ik-intercom-export/2026-11-03/series SPEC=port.yml \
  #     SENDER_ADDRESS_ID=1 EMAIL_TEMPLATE_ID=1
  desc "Create draft Sequences from an Intercom Series export and a port spec"
  task import_intercom_series: :environment do
    team = Team.find(ENV.fetch("TEAM_ID"))
    importer = Sequences::IntercomSeriesImporter.new(
      team: team,
      export_dir: File.expand_path(ENV.fetch("EXPORT_DIR")),
      spec: YAML.safe_load_file(File.expand_path(ENV.fetch("SPEC"))),
      sender_address: ENV["SENDER_ADDRESS_ID"].presence && team.sender_addresses.find(ENV["SENDER_ADDRESS_ID"]),
      # Required: without a template, steps are plain text and markdown ships raw.
      email_template: team.email_templates.find(ENV.fetch("EMAIL_TEMPLATE_ID"))
    )
    importer.call.each do |result|
      puts "#{result.status.to_s.ljust(8)} #{result.name} (#{result.steps} steps)"
      result.changes.each { |c| puts "         - #{c}" }
      result.warnings.each { |w| puts "         ! #{w}" }
    end
  end
end
