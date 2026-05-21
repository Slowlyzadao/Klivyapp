module Billing
module Api
  module V1
    module Billing
      class OnboardingController < ApplicationController
        skip_before_action :verify_authenticity_token, raise: false
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :check_billing_status, raise: false

        before_action :verify_turnstile, only: [:create]
        before_action :validate_coupon, only: [:create]

        def create
          ActiveRecord::Base.transaction do
            # 1. Start by building the Local Account structure BEFORE Asaas
            # So we can pass account.id as externalReference for reconciliation
            builder = AccountBuilder.new(
              account_name: customer_params[:clinic_name] || customer_params[:name],
              email: customer_params[:email],
              user_full_name: customer_params[:name],
              user_password: SecureRandom.urlsafe_base64(16) + 'Aa1#',
              confirmed: true # Allows immediate login, reset instructions sent below
            )
            user, account = builder.perform
            
            # We no longer send the email here. We wait for the second step of onboarding.
            # user.send_reset_password_instructions

            # Generate authentication tokens to auto-login the user immediately on the frontend
            auth_headers = user.create_new_auth_token
            
            # The account is initially suspended. 
            # The Subscription model controls the Account state.
            account.update!(status: :suspended)

            # 2. Check if Enterprise / Lead path
            if plan == 'enterprise'
              ::Billing::Subscription.create!(
                account: account,
                status: :lead,
                plan: plan,
                price: 0.0
              )
              return render json: { 
                status: 'lead', 
                account_id: account.id, 
                message: 'Account created as lead. Redirect to commercial team.' 
              }, status: :created
            end

            # 3. Create customer in Asaas sending externalReference
            customer_id = Asaas::CreateCustomer.new(customer_params, account.id).perform

            # Save customer in local DB map
            local_customer = ::Billing::Customer.create!(
              name: customer_params[:name],
              email: customer_params[:email],
              cpf_cnpj: customer_params[:cpf_cnpj],
              phone: customer_params[:phone],
              asaas_customer_id: customer_id
            )

            # 4. Resolve coupon → plano de ações (delay + avulsas)
            base_price = Asaas::CreateSubscription::PLAN_PRICING[plan]
            coupon_plan = ::Billing::CouponRegistry.plan_for(coupon, base_price)

            if coupon_plan[:free_forever]
              # Admin: não cria subscription nem avulsas no Asaas.
              ::Billing::Subscription.create!(
                account: account,
                status: :active,
                plan: plan,
                price: 0.0,
                asaas_customer_id: customer_id,
                asaas_subscription_id: nil,
                coupon_code: coupon_plan[:coupon_code]
              )

              render json: {
                status: 'active',
                account_id: account.id,
                auth: auth_headers,
                user_data: user.push_event_data,
                message: 'Conta ativada em regime vitalício.'
              }, status: :created
              next
            end

            # 5. Subscription recorrente sempre no valor cheio.
            #    Cupons só adiam nextDueDate (trial) ou geram avulsas (percent).
            sub_result = Asaas::CreateSubscription.new(
              customer_id,
              plan,
              credit_card_params,
              request.remote_ip,
              account.id,
              coupon_code: coupon_plan[:coupon_code],
              start_date: coupon_plan[:subscription_start]
            ).perform

            # 6. Cobranças avulsas para os meses cobertos pelo cupom (percent)
            if coupon_plan[:avulsa_charges].any? && sub_result[:credit_card_token].blank?
              Rails.logger.warn(
                "[Onboarding] Cupom #{coupon_plan[:coupon_code]} exige cobranças avulsas mas o Asaas não retornou creditCardToken. Prosseguindo sem avulsas."
              )
            end

            coupon_plan[:avulsa_charges].each do |charge|
              next if sub_result[:credit_card_token].blank?
              Asaas::CreatePayment.new(
                customer_id: customer_id,
                value: charge[:value],
                due_date: charge[:due_date],
                description: charge[:description],
                credit_card_token: sub_result[:credit_card_token],
                customer_ip: request.remote_ip,
                external_reference: account.id
              ).perform
            end

            # 7. Registro local
            ::Billing::Subscription.create!(
              account: account,
              status: sub_result[:status] == 'ACTIVE' ? :active : :pending,
              plan: plan,
              price: sub_result[:price],
              asaas_customer_id: customer_id,
              asaas_subscription_id: sub_result[:asaas_subscription_id],
              asaas_credit_card_token: sub_result[:credit_card_token],
              coupon_code: coupon_plan[:coupon_code]
            )

            render json: {
              status: 'pending',
              account_id: account.id,
              auth: auth_headers,
              user_data: user.push_event_data,
              message: 'Account created. Waiting for payment confirmation.'
            }, status: :created
          end
        rescue CustomExceptions::Account::UserExists
          render json: {
            error: 'Este e-mail já possui conta. Faça login ou recupere sua senha.',
            code: 'email_already_registered'
          }, status: :unprocessable_entity
        rescue CustomExceptions::Billing::AsaasError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
        rescue StandardError => e
          Rails.logger.error("Onboarding Error: #{e.message}")
          render json: { error: 'Internal Server Error' }, status: :internal_server_error
        end

        def check_email
          email = params[:email].to_s.strip.downcase
          if email.blank? || !email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
            render json: { available: false, reason: 'invalid_email' }
            return
          end

          if User.exists?(email: email)
            render json: { available: false, reason: 'email_already_registered' }
          else
            render json: { available: true }
          end
        end

        def finalize
          # 1. Always resolve the user by the authenticated token (uid header), never by params[:email].
          #    Looking up by params[:email] allowed hijacking ANY existing account by sending its email here.
          user = User.find_by(uid: request.headers['uid'].to_s)
          return render json: { error: 'User not found' }, status: :not_found unless user

          # 2. Verify the access-token/client pair actually belongs to this user.
          client = request.headers['client'].to_s
          token  = request.headers['access-token'].to_s
          unless client.present? && token.present? && user.valid_token?(token, client)
            render json: { error: 'Autenticação inválida. Refaça o checkout.' }, status: :unauthorized
            return
          end

          new_email = params[:email].to_s.strip.downcase
          new_password = params[:password]

          # 3. If admin chose a new email, make sure it isn't already taken by a different account.
          if new_email.present? && new_email != user.email.to_s.downcase
            if User.where(email: new_email).where.not(id: user.id).exists?
              render json: {
                error: 'Este e-mail já está em uso por outra conta.',
                code: 'email_already_registered'
              }, status: :unprocessable_entity
              return
            end
            user.email = new_email
          end

          if new_password.present?
            user.password = new_password
            user.password_confirmation = new_password
          end

          user.save!
          user.send_confirmation_instructions
          render json: { success: true, message: 'Onboarding finished successfully.' }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end

        private

        def plan
          params.require(:selected_plan)
        end

        def customer_params
          params.permit(:name, :clinic_name, :email, :cpf_cnpj, :phone, :address, :address_number, :complement, :province, :postal_code)
        end

        def coupon
          params[:coupon].to_s.strip.upcase
        end

        def validate_coupon
          code = coupon
          return if code.blank? # cupom é opcional
          return if ::Billing::CouponRegistry.valid?(code)

          render json: { error: 'Cupom inválido ou expirado.' }, status: :unprocessable_entity
        end

        def credit_card_params
          params.permit(creditCard: {}, creditCardHolderInfo: {})
        end

        def verify_turnstile
          secret = ENV.fetch('TURNSTILE_SECRET_KEY', nil)
          return if secret.blank?

          token = params[:turnstile_token].to_s
          if token.blank?
            render json: { error: 'Verificação anti-robô ausente. Recarregue a página.' }, status: :unprocessable_entity
            return
          end

          uri = URI('https://challenges.cloudflare.com/turnstile/v0/siteverify')
          http_response = Net::HTTP.post_form(uri, secret: secret, response: token, remoteip: request.remote_ip)
          result = JSON.parse(http_response.body) rescue {}

          unless result['success']
            Rails.logger.warn("[Turnstile] Verification failed: #{result.inspect}")
            render json: { error: 'Verificação anti-robô falhou. Tente novamente.' }, status: :unprocessable_entity
          end
        rescue StandardError => e
          Rails.logger.error("[Turnstile] Exception during verification: #{e.class}: #{e.message}")
          render json: { error: 'Erro ao validar verificação anti-robô.' }, status: :service_unavailable
        end
      end
    end
  end
end
end
