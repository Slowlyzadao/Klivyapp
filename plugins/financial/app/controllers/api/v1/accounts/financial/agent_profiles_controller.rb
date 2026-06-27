module Api
  module V1
    module Accounts
      module Financial
        # Perfil financeiro 1-to-1 com User.
        # Decisão arquitetural 2026-05-22: User core (gerenciado em
        # /settings/agents/list) permanece source of truth de identidade.
        # Aqui ficam apenas campos canon §1 específicos do financeiro:
        # tipo_vinculo (PJ/CLT/Sócio), data_entrada, categoria, comissionável,
        # CRO, especialidades, dados bancários.
        #
        # Index retorna lista de Users (account_users) + profile financeiro
        # quando existe. UI mostra users sem profile destacados ("Sem
        # configuração financeira — comissões/folha não disponíveis").
        class AgentProfilesController < BaseController
          skip_before_action :ensure_setup_complete!, only: %i[index]

          before_action :authorize_write!, only: %i[upsert deactivate]

          # GET /financial/v2/agent_profiles
          # Retorna [{user, profile, stats?}] — profile pode ser null.
          # Query param `include_stats=true` adiciona produção/orçamentos/pacientes
          # por profissional via batch aggregate (sem N+1).
          #
          # Nota: `.distinct` em `User.joins(:account_users)` falha em Postgres
          # com `could not identify an equality operator for type json` porque
          # `users` tem coluna `pubsub_token` ou similar do tipo `json` (não
          # `jsonb`). Usamos two-step query: pluck dos IDs primeiro, depois
          # User.where(id: ...). Mais simples e evita o gotcha do DISTINCT.
          def index
            user_ids = ::AccountUser
                         .where(account_id: current_account.id)
                         .pluck(:user_id)
                         .uniq
            users = ::User.where(id: user_ids).order(:name)

            profiles_by_user = ::Financial::AgentProfile
                                 .for_account(current_account.id)
                                 .alive
                                 .where(user_id: user_ids)
                                 .index_by(&:user_id)

            stats_by_user = include_stats? ? aggregate_stats(user_ids) : {}

            data = users.map do |user|
              entry = { user: serialize_user(user),
                        profile: profiles_by_user[user.id]&.then { |p| serialize_profile(p) } }
              entry[:stats] = stats_by_user[user.id] || empty_stats if include_stats?
              entry
            end
            render json: { data: data }
          end

          # GET /financial/v2/agent_profiles/:user_id
          def show
            user = find_user!(params[:id])
            return unless user

            profile = ::Financial::AgentProfile
                        .for_account(current_account.id)
                        .alive
                        .find_by(user_id: user.id)

            render json: {
              user: serialize_user(user),
              profile: profile ? serialize_profile(profile) : nil
            }
          end

          # PUT /financial/v2/agent_profiles/:user_id
          # Cria ou atualiza profile pro user.
          def upsert
            user = find_user!(params[:id])
            return unless user

            idempotent! do
              profile = ::Financial::AgentProfile
                          .for_account(current_account.id)
                          .alive
                          .find_or_initialize_by(user_id: user.id)
              profile.assign_attributes(profile_params.merge(account_id: current_account.id))

              if profile.save
                render json: serialize_profile(profile), status: profile.previously_new_record? ? :created : :ok
              else
                render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          # DELETE /financial/v2/agent_profiles/:user_id
          # Inativa — User base permanece intacto.
          def deactivate
            user = find_user!(params[:id])
            return unless user

            profile = ::Financial::AgentProfile
                        .for_account(current_account.id)
                        .alive
                        .find_by(user_id: user.id)
            return render(json: { ok: true, already_unconfigured: true }) unless profile

            idempotent_optional! do
              profile.soft_delete!(user: current_user)
              render json: { ok: true }
            end
          end

          private

          def include_stats?
            ActiveModel::Type::Boolean.new.cast(params[:include_stats])
          end

          # Agrega produção/orçamentos/pacientes por professional_id num único
          # query batch — evita N+1 mesmo com dezenas de profissionais.
          #
          # Regras canon:
          # - "produção_real_cents": soma de Budget.total_cents onde
          #   status IN ('aprovado', 'concluido'). Rascunho e cancelado NÃO contam.
          # - "orcamentos_count": todos os budgets não-cancelados (pipeline + realizado)
          # - "pacientes_count": distinct patient_id de budgets não-cancelados
          def aggregate_stats(user_ids)
            return {} if user_ids.empty?

            base = ::Financial::Budget
                     .for_account(current_account.id)
                     .where(professional_id: user_ids)
                     .where.not(status: 'cancelado')

            realized_sum = base
                             .where(status: %w[aprovado concluido])
                             .group(:professional_id)
                             .sum(:total_cents)

            budget_count = base.group(:professional_id).count

            patient_count = base
                              .group(:professional_id)
                              .distinct
                              .count(:patient_id)

            user_ids.each_with_object({}) do |uid, acc|
              acc[uid] = {
                producao_real_cents: realized_sum[uid].to_i,
                orcamentos_count:    budget_count[uid].to_i,
                pacientes_count:     patient_count[uid].to_i
              }
            end
          end

          def empty_stats
            { producao_real_cents: 0, orcamentos_count: 0, pacientes_count: 0 }
          end

          def find_user!(id)
            user = ::User
                     .joins(:account_users)
                     .where(account_users: { account_id: current_account.id })
                     .find_by(id: id)
            unless user
              render json: { error: 'user_not_found_in_account' }, status: :not_found
              return nil
            end
            user
          end

          def authorize_write!
            # Mudança em dados bancários e tipo de vínculo é sensível —
            # ADMIN only (canon §1 "Dados bancários: Para pagamento da comissão")
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])
          end

          def profile_params
            # Ruby 3.4: hash-style args (`key:`) precisam vir DEPOIS dos symbol
            # args. Misturar dá syntax error. Por isso `specialties: []` está
            # no final, mesmo sendo logicamente parte do bloco "perfil".
            params.require(:agent_profile).permit(
              :cpf,
              :agent_category,
              :bond_type,
              :entry_date,
              :commissionable,
              :cro,
              # dados bancários
              :bank_name,
              :bank_agency,
              :bank_account_number,
              :pix_key,
              :status,
              :notes,
              specialties: []
            )
          end

          # Inclui campos pra UI renderizar avatar + badge de função (mesmo
          # padrão de /settings/agents). Frontend usa `klivy_role.name`,
          # `custom_role_id` e `role` pra decidir o label do badge.
          def serialize_user(u)
            account_user = u.account_users.find_by(account_id: current_account.id)
            klivy_role_name = nil
            if account_user&.klivy_role_id.present? && defined?(::KlivyRole)
              klivy_role_name = ::KlivyRole.where(id: account_user.klivy_role_id).pick(:name)
            end

            {
              id: u.id,
              name: u.name,
              email: u.email,
              avatar_url: u.avatar_url.presence,
              role: account_user&.role,
              beclinic_super_admin: u.try(:beclinic_super_admin?) || false,
              custom_role_id: account_user&.custom_role_id,
              klivy_role: klivy_role_name ? { name: klivy_role_name } : nil
            }
          end

          def serialize_profile(p)
            {
              id: p.id,
              user_id: p.user_id,
              cpf: p.cpf,
              agent_category: p.agent_category,
              bond_type: p.bond_type,
              entry_date: p.entry_date,
              commissionable: p.commissionable,
              cro: p.cro,
              specialties: p.specialties || [],
              bank_name: p.bank_name,
              bank_agency: p.bank_agency,
              bank_account_number: p.bank_account_number,
              pix_key: p.pix_key,
              status: p.status,
              notes: p.notes,
              created_at: p.created_at,
              updated_at: p.updated_at
            }
          end
        end
      end
    end
  end
end
