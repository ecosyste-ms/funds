Rails.application.routes.draw do  
  resources :funds, only: [:index, :show] do
    resources :allocations, only: [:show]
    resources :projects, only: [:index]
  end

  resources :projects, only: [:show]

  root "funds#index"
end
