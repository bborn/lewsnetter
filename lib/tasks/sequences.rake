namespace :sequences do
  # Port Intercom Series into draft Sequences. Nothing sends: every sequence
  # is created as a draft for review. DRY_RUN=1 reports without writing.
  # The MCP tool `sequences_import_intercom` runs the same import, one
  # series per call.
  #
  #   bin/rails sequences:import_intercom_series TEAM_ID=1 \
  #     EXPORT_DIR=~/ik-intercom-export/2026-11-03/series SPEC=port.yml \
  #     SENDER_ADDRESS_ID=1 EMAIL_TEMPLATE_ID=1
  desc "Create draft Sequences from an Intercom Series export and a port spec"
  task import_intercom_series: :environment do
    importer = Sequences::IntercomSeriesImporter.for_team(
      Team.find(ENV.fetch("TEAM_ID")),
      export_dir: File.expand_path(ENV.fetch("EXPORT_DIR")),
      spec: YAML.safe_load_file(File.expand_path(ENV.fetch("SPEC"))),
      sender_address_id: ENV["SENDER_ADDRESS_ID"],
      email_template_id: ENV.fetch("EMAIL_TEMPLATE_ID"),
      dry_run: ENV["DRY_RUN"].present?
    )
    importer.call.each do |result|
      puts "#{result.status.to_s.ljust(12)} #{result.name} (#{result.steps} steps)"
      result.changes.each { |c| puts "             - #{c}" }
      result.warnings.each { |w| puts "             ! #{w}" }
    end
  end
end
