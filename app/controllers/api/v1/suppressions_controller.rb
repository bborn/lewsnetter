# Push-API entry point for the per-team suppression list. Source apps call it
# when they learn an address must never be mailed (a bounce or complaint seen
# elsewhere, an opt-out, a GDPR request) so campaigns and sequences both skip
# it from the next send on.
#
# POST /api/v1/teams/:team_id/suppressions
#   {"email": "a@b.com", "reason": "complaint", "note": "optional", "source": "optional"}
#
# Idempotent: re-posting an address returns the existing row (200) with its
# original reason. A new row returns 201.
if defined?(Api::V1::ApplicationController)
  class Api::V1::SuppressionsController < Api::V1::ApplicationController
    def create
      team = Team.find(params[:team_id])
      # Suppression isn't in roles.yml; like the account UI, managing the
      # team's blocklist needs Team#manage (admins, including sync tokens).
      authorize! :manage, team

      email = params[:email].to_s.strip.downcase
      return render(json: {error: "email is required"}, status: :bad_request) if email.blank?

      reason = params[:reason].presence || "manual"
      unless Suppression::REASONS.include?(reason)
        return render(json: {error: "reason must be one of #{Suppression::REASONS.join(", ")}"},
          status: :unprocessable_entity)
      end

      existed = team.suppressions.where(email: email).exists?
      suppression = Suppression.suppress(
        team: team, email: email, reason: reason,
        source: params[:source].presence || "api", note: params[:note].presence
      )

      render json: {
        email: suppression.email,
        reason: suppression.reason,
        source: suppression.source,
        note: suppression.note,
        suppressed_at: suppression.suppressed_at,
        created: !existed
      }, status: existed ? :ok : :created
    rescue ActiveRecord::RecordInvalid => e
      render json: {error: e.record.errors.full_messages.to_sentence}, status: :unprocessable_entity
    end
  end
else
  class Api::V1::SuppressionsController
  end
end
