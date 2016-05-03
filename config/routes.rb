# Route prefixes use a single letter to allow for vanity urls of two or more characters
Rails.application.routes.draw do

  mount Ckeditor::Engine => '/ckeditor'

  if defined? Sidekiq
    require 'sidekiq/web'
    authenticate :user, lambda {|u| u.is_admin? } do
      mount Sidekiq::Web, at: '/admin/sidekiq/jobs', as: :sidekiq
    end
  end

  mount RailsAdmin::Engine => '/admin', :as => 'rails_admin' if defined? RailsAdmin

  # Static pages
  match '/error' => 'pages#error', via: [:get, :post], as: 'error_page'
  get '/terms' => 'pages#terms', as: 'terms'
  get '/privacy' => 'pages#privacy', as: 'privacy'

  # OAuth
  oauth_prefix = Rails.application.config.auth.omniauth.path_prefix
  get "#{oauth_prefix}/:provider/callback" => 'users/oauth#create'
  get "#{oauth_prefix}/failure" => 'users/oauth#failure'
  get "#{oauth_prefix}/:provider" => 'users/oauth#passthru', as: 'provider_auth'
  get oauth_prefix => redirect("#{oauth_prefix}/login")

  # Devise
  devise_prefix = Rails.application.config.auth.devise.path_prefix
  devise_for :users, path: devise_prefix,
    controllers: {registrations: 'users/registrations', sessions: 'users/sessions',
      passwords: 'users/passwords', confirmations: 'users/confirmations', unlocks: 'users/unlocks'},
    path_names: {sign_up: 'signup', sign_in: 'login', sign_out: 'logout'}
  devise_scope :user do
    get "#{devise_prefix}/after" => 'users/registrations#after_auth', as: 'user_root'
  end
  get devise_prefix => redirect('/a/signup')

  # User
  resources :users, path: 'u', only: :show do
    resources :authentications, path: 'accounts'
  end
  get '/home' => 'users#show', as: 'user_home'


  resources :campaigns do
    member do
      get 'edit_content_iframe' => 'campaigns#edit_content_iframe'
      get 'edit_content' => 'campaigns#edit_content'
      patch 'update_content' => 'campaigns#update_content'
      patch 'send_preview' => 'campaigns#send_preview'
      get 'send' => 'campaigns#send_campaign'
      get 'queue'
      get 'get_feed' => 'campaigns#get_feed'
      get 'webview'   => 'campaigns#webview'
    end
  end

  resources :subscriptions do
    post :create, as: 'subscribe'
    member do
      get 'unsubscribe'
      get 'subscribe'
      get 'confirm'
    end
  end

  resources :mailing_lists do
    member do
      match 'import', via: [:patch, :get]
    end
  end

  resources :templates


  post 'bounces' => 'deliveries#bounce'
  post 'deliveries' => 'deliveries#delivered'
  post 'complaints' => 'deliveries#complaint'
  get  'opened' => 'deliveries#opened'

  # Dummy preview pages for testing.
  get '/p/test' => 'pages#test', as: 'test'
  get '/p/email' => 'pages#email' if ENV['ALLOW_EMAIL_PREVIEW'].present?

  get 'robots.:format' => 'robots#index'

  root 'campaigns#index'
end
