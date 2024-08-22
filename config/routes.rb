Rails.application.routes.draw do  
  resources :funds, only: [:index, :show] do
    resources :allocations, only: [:show]
  end

  root "funds#index"
end
