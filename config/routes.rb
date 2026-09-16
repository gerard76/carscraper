Rails.application.routes.draw do
  resources :models
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  root to: "models#index"
  resources :cars do
    member do
      # One click to put a car away, and one to get it back.
      patch :hide
      patch :unhide
    end

    collection do
      # The same cars as the graph, as a table you can sort.
      get :table

      # And as a wall of photographs.
      get :photos

      # What you clicked away, and nothing else.
      get :bin
    end
  end
end
