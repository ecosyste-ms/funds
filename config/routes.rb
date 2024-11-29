require 'sidekiq_unique_jobs/web'
require 'sidekiq/web'

Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])) &
    ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"]))
end if Rails.env.production?

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"
  mount PgHero::Engine, at: "pghero"
  
  resources :funds, only: [:index, :show] do
    member do
      get :transactions
    end
    resources :allocations, only: [:show] do |allocations|
      member do
        get :export
        get :export_github_sponsors
      end
    end
    resources :projects, only: [:index]
  end

  resource :invitation do
    member do
      post :accept
      post :reject
    end
  end

  resources :funding_sources, only: [:index, :show]

  resources :projects, only: [:show]

  get '/about', to: 'pages#about'
  get '/faq', to: 'pages#faq'
  get '/privacy', to: 'pages#privacy'
  get '/overview', to: 'pages#overview'
  get '/terms', to: 'pages#terms'

  post '/webhooks', to: 'webhooks#receive'

  get '/404', to: 'errors#not_found'
  get '/422', to: 'errors#unprocessable'
  get '/500', to: 'errors#internal'
  get '/403', to: 'errors#forbidden'
  get '/401', to: 'errors#unauthorized'
  get '/400', to: 'errors#bad_request'
  get '/409', to: 'errors#conflict'
  get '/503', to: 'errors#service_unavailable'
  get '/429', to: 'errors#too_many_requests'

  root "funds#index"
end
