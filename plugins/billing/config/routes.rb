Billing::Engine.routes.draw do
  namespace :api do
    namespace :v1 do
      namespace :billing do
        post 'onboarding', to: 'onboarding#create'
        post 'onboarding/finalize', to: 'onboarding#finalize'
        get  'onboarding/check_email', to: 'onboarding#check_email'
        post 'webhooks/asaas', to: 'webhooks#asaas'
        get  'subscription', to: 'subscription#show'
      end
    end
  end
end
