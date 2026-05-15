Rails.application.routes.draw do
  # Rails 8 default health endpoint used by Kamal's proxy + load balancers.
  # Returns 200 if the app can boot; otherwise 500. BulletTrain's stock
  # routes.rb doesn't include this — adding it here keeps the deploy
  # healthcheck wired correctly.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public signup lockdown. Lewsnetter is in private alpha; only invited
  # users (via the BulletTrain invitation flow at /account/teams/:id/
  # invitations/new) can create an account. The Devise sign-up form +
  # POST endpoint are both shadowed to a redirect.
  #
  # To open the gates: set LEWSNETTER_PUBLIC_SIGNUPS=true in kamal env and
  # redeploy. Sign-in / password reset / invitations are unaffected.
  unless ActiveModel::Type::Boolean.new.cast(ENV["LEWSNETTER_PUBLIC_SIGNUPS"])
    get "/users/sign_up", to: redirect("/users/sign_in?signup_disabled=1")
    post "/users", to: redirect("/users/sign_in?signup_disabled=1")
  end

  # Public unsubscribe endpoint. Mounted BEFORE the BulletTrain engines so it
  # can be hit without authentication. Both GET (link click) and POST
  # (RFC 8058 one-click) hit the same controller.
  get "/unsubscribe/:token", to: "unsubscribe#update", as: :unsubscribe
  post "/unsubscribe/:token", to: "unsubscribe#update"

  # Public SNS webhook for SES bounce + complaint notifications. Mounted
  # BEFORE the BulletTrain engines so SNS can hit it without auth. Each
  # tenant points their SNS topic at this URL; routing back to the right
  # team happens via Team::SesConfiguration topic ARN lookup.
  post "/webhooks/ses/sns", to: "webhooks/ses/sns#create"

  # OAuth 2.1 discovery + RFC 7591 dynamic client registration for MCP.
  # Mounted BEFORE the BulletTrain engines so they're publicly readable
  # (no Devise auth required to fetch the metadata or register a client).
  # See app/controllers/well_known_controller.rb and
  # app/controllers/oauth/registrations_controller.rb.
  get "/.well-known/oauth-protected-resource", to: "well_known#oauth_protected_resource"
  get "/.well-known/oauth-authorization-server", to: "well_known#oauth_authorization_server"
  post "/oauth/register", to: "oauth/registrations#create"

  # MCP server. Token-authed via Mcp::DoorkeeperAuth middleware (composed
  # inline below). Mounted BEFORE the BulletTrain engines so it skips
  # Devise/CSRF and runs as a pure Rack endpoint. Routes POST + GET to
  # the same Rack app — GET is used by clients that upgrade to SSE for
  # streamable HTTP.
  mount Rack::Builder.new {
    use Mcp::DoorkeeperAuth
    run ->(env) { Mcp::Server.rack_app.call(env) }
  } => "/mcp"

  # See `config/routes/*.rb` to customize these configurations.
  draw "concerns"
  draw "devise"
  draw "sidekiq"
  draw "avo"

  # `collection_actions` is automatically super scaffolded to your routes file when creating certain objects.
  # This is helpful to have around when working with shallow routes and complicated model namespacing. We don't use this
  # by default, but sometimes Super Scaffolding will generate routes that use this for `only` and `except` options.
  collection_actions = [:index, :new, :create] # standard:disable Lint/UselessAssignment

  # This helps mark `resources` definitions below as not actually defining the routes for a given resource, but just
  # making it possible for developers to extend definitions that are already defined by the `bullet_train` Ruby gem.
  # TODO Would love to get this out of the application routes file.
  extending = {only: []}

  scope module: "public" do
    # To keep things organized, we put non-authenticated controllers in the `Public::` namespace.
    # The root `/` path is routed to `Public::HomeController#index` by default. You can set it
    # to whatever you want by doing something like this:
    # root to: "my_new_root_controller#index"
  end

  namespace :webhooks do
    namespace :incoming do
      namespace :oauth do
        # 🚅 super scaffolding will insert new oauth provider webhooks above this line.
      end
    end
  end

  namespace :api do
    draw "api/v1"
    # 🚅 super scaffolding will insert new api versions above this line.
  end

  # Friendlier-than-404 redirect for bare shallow paths. BulletTrain's shallow
  # routes only mount `/account/:resource/:id` (show/edit/destroy) and the
  # bare `/account/:resource` lives under a team scope. We send users to
  # /account so they can pick a team rather than face a hard 404. No UI in
  # the app links here today; this is for hand-typed URLs and stale bookmarks.
  get "/account/campaigns", to: redirect("/account")
  get "/account/segments", to: redirect("/account")
  get "/account/subscribers", to: redirect("/account")
  get "/account/email_templates", to: redirect("/account")
  get "/account/sender_addresses", to: redirect("/account")

  namespace :account do
    shallow do
      # The account root `/` path is routed to `Account::Dashboard#index` by default. You can set it
      # to whatever you want by doing something like this:
      # root to: "some_other_root_controller#index", as: "dashboard"

      # user-level onboarding tasks.
      namespace :onboarding do
        # routes for standard onboarding steps are configured in the `bullet_train` gem, but you can add more here.
      end

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

        # Variables (built-ins + custom_attribute keys) available for
        # campaign interpolation. Drives the "Insert variable" picker on
        # the campaign edit form.
        get :variables, to: "team_variables#index", as: :variables

        resources :subscribers do
          collection do
            # Typeahead JSON for the "Preview as" autocomplete on the campaign
            # show page. See Account::SubscribersController#search.
            get :search
          end
          resources :events
        end

        # Subscribers::Import — CSV upload + background processing. A sibling
        # of subscribers (not nested under) because imports are tenant-scoped,
        # not subscriber-scoped.
        namespace :subscribers do
          resources :imports, only: %i[index new create show]
        end

        resources :segments do
          collection do
            post :translate, to: "segment_translations#create"
          end
        end
        resources :email_templates do
          member do
            get :preview_frame
            # Asset uploads (images, primarily logos) are scoped per-template
            # so the asset_id in the URL refers to an ActiveStorage::Attachment
            # row. We `purge_later` rather than `purge` so a slow R2 delete
            # doesn't block the redirect.
            delete "assets/:asset_id", to: "email_templates#destroy_asset", as: :asset
          end
        end
        resources :campaigns do
          member do
            post :send_now
            post :test_send
            post :preview_as
            post :draft, to: "campaign_drafts#create"
            get :postmortem, to: "campaign_postmortems#show"
            # GET serves the saved-state preview (used as an iframe `src` for
            # backwards compat and direct linking). POST accepts in-memory
            # form values so the editor can live-render without persisting.
            get :preview_frame
            post :preview_frame
            # Drag-and-drop image upload from the markdown editor. Attaches a
            # file to the campaign's assets collection and returns JSON
            # { url, name } so the editor can splice `![name](url)` at the
            # cursor.
            post "assets", to: "campaigns#upload_asset", as: :upload_asset
            # See email_templates above — same purge_later pattern.
            delete "assets/:asset_id", to: "campaigns#destroy_asset", as: :asset
          end
        end
        resources :sender_addresses do
          member do
            post :recheck
            # Adds the address to SES (or re-uses an existing identity)
            # which triggers SES to send a verification email. Surfaced
            # on the show page when the address isn't yet verified (U11).
            post :verify_with_ses
          end
        end

        resources :chats, only: [:index, :show, :create, :destroy]

        # Singleton "Email Sending" page — there's at most one
        # Team::SesConfiguration per team. We use member routes rather than
        # a `resource :email_sending` so the URLs read naturally
        # (/account/teams/:team_id/email_sending) and we have explicit verbs
        # for verify + import_identity.
        get "email_sending", to: "email_sending#show", as: :email_sending
        patch "email_sending", to: "email_sending#update"
        put "email_sending", to: "email_sending#update"
        post "email_sending/verify", to: "email_sending#verify", as: :verify_email_sending
        post "email_sending/import_identity", to: "email_sending#import_identity", as: :import_identity_email_sending
      end
    end
  end
end
