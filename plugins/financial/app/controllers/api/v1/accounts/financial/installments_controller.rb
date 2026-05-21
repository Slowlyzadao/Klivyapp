module Api
  module V1
    module Accounts
      module Financial
        class InstallmentsController < BaseController
          before_action :set_installment, only: %i[show pay refund charge_whatsapp upload_proof proof_url]

          # GET /financial/v2/installments — Tela A Receber.
          # Aceita filtro multi-status via array (status[]=pendente&status[]=vencido)
          # ou string única (status=pendente). Útil pra default da UI mostrar
          # só parcelas em aberto sem bloquear a flexibilidade de filtrar 1 só.
          def index
            scope = ::Financial::Installment.for_account(current_account.id)
            if params[:status].present?
              statuses = Array(params[:status]).flatten.reject(&:blank?)
              scope = scope.where(status: statuses) if statuses.any?
            end
            scope = scope.where(patient_id: params[:patient_id]) if params[:patient_id].present?
            scope = scope.where(professional_id: params[:professional_id]) if params[:professional_id].present?
            scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?
            scope = scope.where('due_date >= ?', params[:from]) if params[:from].present?
            scope = scope.where('due_date <= ?', params[:to])   if params[:to].present?
            if params[:q].present?
              # Explicita `patients.account_id` no JOIN como defesa em
              # profundidade — o scope já vem `.for_account`, mas o filtro
              # explícito deixa o intent multi-tenant claro pro leitor.
              scope = scope.joins(:patient)
                           .where(patients: { account_id: current_account.id })
                           .where('LOWER(patients.name) LIKE ?', "%#{params[:q].to_s.downcase}%")
            end

            sort = params[:sort] || 'due_date'
            direction = params[:direction] == 'desc' ? :desc : :asc
            scope = scope.order(sort => direction, created_at: :desc)

            page = (params[:page] || 1).to_i
            per_page = [(params[:per_page] || 25).to_i, 100].min
            total = scope.count
            # `budget: :items` evita N+1 ao montar `description` do budget
            # (que lê `b.notes` ou nome do primeiro item).
            installments = scope.includes(:patient, :professional, budget: :items)
                                .offset((page - 1) * per_page).limit(per_page)

            render json: {
              data: installments.map { |i| serialize(i, include_budget: true) },
              meta: {
                page: page, per_page: per_page, total: total,
                total_to_receive_cents: scope.where(status: %w[pendente vencido parcial]).sum('amount_cents - received_amount_cents'),
                total_received_cents: scope.where(status: 'recebido').sum(:received_amount_cents),
                total_overdue_cents: scope.where(status: 'pendente').where('due_date < ?', Date.current).sum('amount_cents - received_amount_cents'),
                total_count: total
              }
            }
          end

          def show
            render json: serialize(@installment, include_budget: true, include_receipts: true)
          end

          # GET /financial/v2/installments/by_patient
          # Variante agrupada da listagem A Receber. Aceita os mesmos filtros
          # do `index` mas pagina por PACIENTE (não por parcela). Cada item
          # traz já as parcelas filtradas embutidas — frontend só precisa
          # alternar visibilidade ao expandir (sem 2ª request).
          #
          # Resposta:
          #   data: [
          #     {
          #       patient: { id, name, avatar_url },
          #       summary: { count, total_remaining_cents, overdue_count,
          #                  overdue_remaining_cents, next_due_date },
          #       installments: [...]
          #     }, ...
          #   ]
          def by_patient
            scope = ::Financial::Installment.for_account(current_account.id)
            if params[:status].present?
              statuses = Array(params[:status]).flatten.reject(&:blank?)
              scope = scope.where(status: statuses) if statuses.any?
            end
            scope = scope.where(patient_id: params[:patient_id]) if params[:patient_id].present?
            scope = scope.where(professional_id: params[:professional_id]) if params[:professional_id].present?
            scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?
            scope = scope.where('due_date >= ?', params[:from]) if params[:from].present?
            scope = scope.where('due_date <= ?', params[:to])   if params[:to].present?
            if params[:q].present?
              # Explicita `patients.account_id` no JOIN como defesa em
              # profundidade — o scope já vem `.for_account`, mas o filtro
              # explícito deixa o intent multi-tenant claro pro leitor.
              scope = scope.joins(:patient)
                           .where(patients: { account_id: current_account.id })
                           .where('LOWER(patients.name) LIKE ?', "%#{params[:q].to_s.downcase}%")
            end

            page = (params[:page] || 1).to_i
            per_page = [(params[:per_page] || 10).to_i, 50].min

            # Lista de patient_ids ordenada pelo próximo vencimento (NULLS por
            # último). Pacientes com parcela vencida sobem naturalmente.
            patient_ids_ordered = scope
              .group(:patient_id)
              .order(Arel.sql('MIN(due_date) ASC NULLS LAST'))
              .pluck(:patient_id)
            total_patients = patient_ids_ordered.size
            paged_ids = patient_ids_ordered[(page - 1) * per_page, per_page] || []

            # Carrega todas as parcelas dos pacientes da página (mesmos filtros).
            installments_in_page = scope
              .where(patient_id: paged_ids)
              .includes(:patient, budget: :items)
              .order(:due_date, :number)

            grouped = installments_in_page.group_by(&:patient_id)
            today = Date.current

            data = paged_ids.map do |pid|
              insts = grouped[pid] || []
              next nil if insts.empty?

              patient = insts.first.patient
              # "Em aberto" = pendente/parcial/vencido.
              open_insts = insts.select { |i| %w[pendente parcial vencido].include?(i.status) }
              overdue = open_insts.select { |i| i.due_date && i.due_date < today }
              next_due_inst = open_insts.select { |i| i.due_date && i.due_date >= today }.min_by(&:due_date)
              # Se não tem nenhuma futura, pega a vencida mais antiga.
              next_due_inst ||= overdue.min_by(&:due_date)

              {
                patient: serialize_patient(patient, pid),
                summary: {
                  count: insts.size,
                  open_count: open_insts.size,
                  total_remaining_cents: open_insts.sum(&:remaining_cents),
                  overdue_count: overdue.size,
                  overdue_remaining_cents: overdue.sum(&:remaining_cents),
                  next_due_date: next_due_inst&.due_date,
                },
                installments: insts.map { |i| serialize(i, include_budget: true) },
              }
            end.compact

            render json: {
              data: data,
              meta: {
                page: page,
                per_page: per_page,
                total: total_patients,
                # Totais agregados (mesma régua do `index`) — para os KPIs.
                total_to_receive_cents: scope.where(status: %w[pendente vencido parcial]).sum('amount_cents - received_amount_cents'),
                total_received_cents: scope.where(status: 'recebido').sum(:received_amount_cents),
                total_overdue_cents: scope.where(status: 'pendente').where('due_date < ?', today).sum('amount_cents - received_amount_cents'),
                total_installments: scope.count,
              }
            }
          end

          # POST /financial/v2/installments/:id/pay
          # Endpoint simplificado para a aba do paciente: paga uma installment
          # individual delegando ao service Financial::ReceivePayment.
          # Aceita baixa parcial (canon BUG-01) via `amount_cents` < remaining.
          #
          # Payload:
          #   {
          #     payment_method: 'pix',                # obrigatório
          #     paid_at: '2026-05-08',                # opcional, default hoje
          #     bank_account_id: 12,                  # opcional, default primeira conta
          #     amount_cents: 27000,                  # opcional, default = remaining
          #     interest_cents: 0, fine_cents: 0, discount_cents: 0,
          #     keep_installment_open: true           # BUG-01: mantém saldo em nova parcela
          #   }
          def pay
            idempotent! do
              bank_account = resolve_bank_account
              return render(json: { errors: ['Conta bancária não encontrada'] }, status: :unprocessable_entity) unless bank_account

              amount_cents = params[:amount_cents].present? ? params[:amount_cents].to_i : @installment.remaining_cents

              result = ::Financial::ReceivePayment.call(
                account: current_account,
                actor: current_user,
                bank_account: bank_account,
                installment_amounts: [{ installment_id: @installment.id, amount_cents: amount_cents }],
                payment_method: params[:payment_method] || @installment.payment_method,
                received_at: params[:paid_at] || params[:received_at],
                interest_cents: params[:interest_cents].to_i,
                fine_cents: params[:fine_cents].to_i,
                discount_cents: params[:discount_cents].to_i,
                apply_patient_credit_cents: params[:apply_patient_credit_cents].to_i,
                notes: params[:notes],
                keep_installment_open: params[:keep_installment_open] != 'false' && params[:keep_installment_open] != false
              )

              if result.success?
                render json: serialize(@installment.reload, include_receipts: true)
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/installments/:id/refund
          # Estorna o último PaymentReceipt que quitou esta installment.
          #
          # Aceita do form do paciente:
          #   amount_cents             — opcional. Valor a estornar em centavos.
          #                              Default = saldo ainda não estornado do recibo.
          #                              Menor que o total → estorno parcial (parcela vira 'parcial').
          #   notes                    — opcional. Motivo do estorno (vai pra audit + descrição da Entry).
          #   payment_method           — opcional. Método de devolução (informativo na descrição).
          #   generate_patient_credit  — opcional. Se 'true', estorna como crédito do paciente
          #                              (sem saída de caixa). Default false (devolução real via método original).
          def refund
            idempotent! do
              receipt = @installment.payment_receipt_items.order(created_at: :desc).first&.receipt
              return render(json: { errors: ['Parcela não tem recibo de pagamento ativo'] }, status: :unprocessable_entity) unless receipt

              reason = [params[:notes], params[:payment_method].presence && "via #{params[:payment_method].to_s.upcase}"]
                       .compact.reject(&:blank?).join(' · ').presence

              as_credit = ActiveModel::Type::Boolean.new.cast(params[:generate_patient_credit])

              result = ::Financial::RefundPayment.call(
                receipt: receipt,
                actor: current_user,
                reason: reason,
                refund_amount_cents: params[:amount_cents].presence&.to_i,
                as_credit: as_credit
              )

              if result.success?
                render json: serialize(@installment.reload, include_receipts: true)
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/installments/:id/charge_whatsapp
          # Monta a mensagem de cobrança e devolve `{phone, whatsapp_message}` para
          # o frontend abrir wa.me — mesmo padrão do legacy
          # (Patients::TransactionsController#charge_whatsapp). Sem envio em
          # background — operador clica e o WhatsApp abre com mensagem pronta.
          def charge_whatsapp
            patient = @installment.patient
            return render(json: { errors: ['Paciente não encontrado'] }, status: :unprocessable_entity) unless patient

            phone = patient.phone.presence
            return render(json: { errors: ['Paciente sem telefone cadastrado'] }, status: :unprocessable_entity) unless phone

            amount_remaining = ::Financial::Concerns::MoneyAttribute.format_brl(@installment.remaining_cents)
            due_formatted = @installment.due_date&.strftime('%d/%m/%Y')

            message = "Olá, #{patient.name}! 👋\n\n" \
                      "Identificamos uma parcela em aberto:\n" \
                      "💰 Valor: #{amount_remaining}\n" \
                      "📅 Vencimento: #{due_formatted}\n\n" \
                      'Entre em contato conosco para regularizar. ' \
                      'Aceitamos PIX, cartão e dinheiro. 😊'

            render json: {
              phone: phone,
              whatsapp_message: message,
              message: 'Cobrança preparada — abrir wa.me no frontend'
            }
          end

          # POST /financial/v2/installments/:id/upload_proof  (multipart)
          # Anexa um comprovante de pagamento à parcela via Active Storage.
          def upload_proof
            file = params[:file] || params[:proof_file]
            return render(json: { errors: ['Arquivo não enviado'] }, status: :unprocessable_entity) unless file

            @installment.payment_proof.attach(file)
            render json: { url: signed_proof_url(@installment), filename: file.original_filename }
          rescue StandardError => e
            render json: { errors: [e.message] }, status: :unprocessable_entity
          end

          # GET /financial/v2/installments/:id/proof_url
          # Retorna URL signed (15 min) para visualizar o comprovante.
          def proof_url
            return render(json: { url: nil }) unless @installment.payment_proof.attached?

            render json: { url: signed_proof_url(@installment) }
          end

          private

          def signed_proof_url(installment)
            Rails.application.routes.url_helpers.rails_blob_url(
              installment.payment_proof,
              host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
              expires_in: 15.minutes
            )
          end

          def resolve_bank_account
            if params[:bank_account_id].present?
              ::Financial::BankAccount.for_account(current_account.id).find_by(id: params[:bank_account_id])
            else
              ::Financial::BankAccount.for_account(current_account.id).where(active: true).first
            end
          end

          def set_installment
            @installment = ::Financial::Installment.for_account(current_account.id).find(params[:id])
          end

          def serialize_patient(patient, fallback_id = nil)
            return { id: fallback_id, name: nil, avatar_url: nil } unless patient
            {
              id: patient.id,
              name: patient.name,
              # `resolved_avatar_url` cobre os 2 caminhos do Patient model:
              # 1. Foto Active Storage (Patient.avatar attached — upload via Cadastro)
              # 2. URL externa em `avatar_url` (foto do WhatsApp, p.ex.)
              avatar_url: patient.try(:resolved_avatar_url),
            }
          end

          def serialize(i, include_budget: false, include_receipts: false)
            # `effective_status` espelha a lógica do PatientTimelinesController
            # (pendente + venceu → vencido). Necessário pra UI mostrar badge
            # ruby quando a parcela está atrasada — antes mostrava só "pendente"
            # cinza e o usuário não conseguia ver qual era a vencida.
            effective_status = compute_effective_status(i)

            data = {
              id: i.id,
              budget_id: i.financial_budget_id,
              patient: serialize_patient(i.patient, i.patient_id),
              professional_id: i.professional_id,
              number: i.number,
              total_in_series: i.total_in_series,
              amount_cents: i.amount_cents,
              received_amount_cents: i.received_amount_cents,
              remaining_cents: i.remaining_cents,
              status: i.status,
              effective_status: effective_status,
              payment_method: i.payment_method,
              due_date: i.due_date,
              competence_date: i.competence_date,
              received_at: i.received_at,
              gateway: i.gateway,
              payment_link: i.payment_link,
              barcode_line: i.barcode_line,
              pix_qr_code: i.pix_qr_code,
              replaces_installment_id: i.replaces_installment_id
            }
            data[:budget] = budget_summary(i.budget) if include_budget && i.budget
            data[:receipts] = i.payment_receipt_items.map(&:receipt).compact.uniq.map(&method(:receipt_summary)) if include_receipts
            data
          end

          def budget_summary(b)
            # `display_id` preserva o número visível do orçamento original
            # do legacy quando a migração gravou em `metadata.legacy_id`.
            # Espelha PatientTimelinesController#derive_origin_label.
            display_id = b.metadata&.dig('legacy_id') || b.id
            label = if b.treatment_plan_id.present?
                      "Plano de Tratamento ##{b.treatment_plan_id}"
                    elsif b.origin == 'mensalidade'
                      "Mensalidade ##{display_id}"
                    else
                      "Orçamento ##{display_id}"
                    end
            {
              id: b.id,
              display_id: display_id,
              status: b.status,
              total_cents: b.total_cents,
              origin: b.origin,
              treatment_plan_id: b.treatment_plan_id,
              label: label,
              # `description` é a descrição amigável do orçamento — derivada
              # do mesmo jeito que PatientTimelinesController#derive_description:
              #   1. notes (se preenchidas pelo operador)
              #   2. nome do primeiro item ("canal no dente superior")
              #   3. fallback pro label técnico
              # Usado pra reduzir fricção na lista A Receber: em vez de "#5"
              # repetido, mostra "Orçamento canal no dente superior".
              description: budget_description(b),
            }
          end

          def budget_description(b)
            return b.notes.to_s.strip if b.notes.present?
            first_item = b.items.first
            return first_item.description if first_item&.description.present?
            nil
          end

          # Mesmo critério de PatientTimelinesController: parcela `pendente`
          # ou `parcial` com data de vencimento passada vira `vencido` na UI.
          # Mantém o `status` cru pra filtros backend e adiciona
          # `effective_status` pra renderização visual consistente.
          def compute_effective_status(inst)
            today = Date.current
            base = inst.status
            return base unless %w[pendente parcial].include?(base)
            return 'vencido' if inst.due_date && inst.due_date < today
            base
          end

          def receipt_summary(r)
            { id: r.id, receipt_number: r.receipt_number, gross_amount_cents: r.gross_amount_cents, received_at: r.received_at }
          end
        end
      end
    end
  end
end
