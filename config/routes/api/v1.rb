# See `config/routes.rb` for details.
collection_actions = [:index, :new, :create] # standard:disable Lint/UselessAssignment
extending = {only: []}

shallow do
  namespace :v1 do
    # user specific resources.
    resources :users, extending do
      namespace :oauth do
        # 🚅 super scaffolding will insert new oauth providers above this line.
      end

      # routes for standard user actions and resources are configured in the `bullet_train` gem, but you can add more here.
    end

    # team-level resources.
    resources :teams, extending do
      # routes for many teams actions and resources are configured in the `bullet_train` gem, but you can add more here.

      # add your resources here.

      resources :invitations, extending do
        # routes for standard invitation actions and resources are configured in the `bullet_train` gem, but you can add more here.
      end

      resources :memberships, extending do
        # routes for standard membership actions and resources are configured in the `bullet_train` gem, but you can add more here.
      end

      namespace :integrations do
        # 🚅 super scaffolding will insert new integration installations above this line.
      end

      resources :subscribers do
        collection do
          # Push-API bulk endpoints. NDJSON body, idempotent upsert by
          # external_id. Source apps wire to these from the lewsnetter-rails
          # gem (or any HTTP client) for backfills.
          post :bulk
          delete "by_external_id/:external_id" => "subscribers#destroy_by_external_id",
            as: :destroy_by_external_id, constraints: {external_id: %r{[^/]+}}
        end

        resources :events
      end

      # Push-API event endpoints — scoped under team, resolve subscriber by
      # external_id from the payload (source apps don't know our internal IDs).
      post "events/track", to: "events#track"
      post "events/bulk", to: "events#bulk"

      resources :segments
      resources :email_templates
      resources :campaigns
      resources :sender_addresses
    end
  end
end
