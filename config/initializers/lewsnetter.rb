# Lewsnetter client configuration.
#
# This Lewsnetter app dogfoods its own client gem against itself. In a real
# host app, set `endpoint` to "https://app.lewsnetter.com/api/v1".
#
# To mint a Platform::AccessToken for local testing:
#
#   bin/rails runner '
#     team = Team.first || Team.create!(name: "Local Dogfood")
#     app  = Doorkeeper::Application.create!(name: "local", redirect_uri: "", scopes: "read write", team: team)
#     token = Platform::AccessToken.create!(application: app, resource_owner_id: team.users.first&.id, scopes: "read write")
#     puts "TOKEN=#{token.token}"
#     puts "TEAM_ID=#{team.id}"
#   '
#
# Then either:
#   - put the values in Rails credentials under :lewsnetter_api_key / :lewsnetter_team_id, or
#   - export LEWSNETTER_API_KEY / LEWSNETTER_TEAM_ID in your .env.
#
# This initializer no-ops if neither source is present so boot stays clean.

api_key =
  Rails.application.credentials.dig(:lewsnetter, :api_key) ||
  Rails.application.credentials.lewsnetter_api_key ||
  ENV["LEWSNETTER_API_KEY"]

team_id =
  Rails.application.credentials.dig(:lewsnetter, :team_id) ||
  Rails.application.credentials.lewsnetter_team_id ||
  ENV["LEWSNETTER_TEAM_ID"]

endpoint =
  Rails.application.credentials.dig(:lewsnetter, :endpoint) ||
  ENV["LEWSNETTER_ENDPOINT"] ||
  "http://localhost:3000/api/v1"

if api_key && team_id
  Lewsnetter.configure do |c|
    c.api_key = api_key
    c.team_id = team_id.to_i
    c.endpoint = endpoint
    c.logger = Rails.logger
    # c.async = false   # uncomment to bypass ActiveJob in dev
  end
end
