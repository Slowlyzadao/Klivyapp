class BackfillPatientResponsibleProfessional < ActiveRecord::Migration[7.0]
  # Backfill data migration — preenche `patients.responsible_professional_id`
  # para pacientes que estão com NULL, usando o user_id do 1º agendamento
  # cronológico do paciente como sinal.
  #
  # Contexto (decisão Mamedes 2026-05-11):
  # Originalmente o composable `useResponsibleProfessional` fazia fallback
  # silencioso pro usuário logado quando o paciente não tinha responsável
  # — comportamento enganoso porque cada user via um nome diferente. Foi
  # corrigido pra mostrar "Sem profissional atribuído" honestamente.
  #
  # Mas isso deixou pacientes legados (importados Clinicorp + cadastros
  # manuais sem ação) com empty state mesmo tendo histórico claro de
  # atendimento. Esta migration faz o backfill 1x:
  #
  #   Para cada Patient com responsible_professional_id NULL:
  #     1. Acha o 1º AgendaEvent (created_at ASC) onde contact_id = patient.contact_id
  #     2. Se existir e tiver user_id, salva como responsible_professional_id
  #     3. Senão, mantém NULL (UI mostra "Sem profissional atribuído")
  #
  # Idempotente: roda 1x no deploy. Não sobrescreve valores já setados.
  # Multi-tenant: não hardcoda nenhum dentista específico — cada conta
  # recebe a atribuição correta baseada no histórico próprio.
  #
  # Daqui pra frente, os callbacks `after_create_commit` em SessionLog,
  # TreatmentPlan, Financial::Budget e AgendaEvent garantem que novos
  # pacientes ganhem responsável automaticamente na 1ª ação relevante.

  disable_ddl_transaction!  # Operação longa em contas grandes (Mamedes tem ~2.500 pacientes)

  def up
    say "Backfill: atribuindo responsible_professional_id via 1º agendamento de cada paciente..."

    total_updated = 0
    total_skipped = 0
    accounts_processed = 0

    # `account_id` é o filtro de tenant — processa conta por conta.
    Account.find_each do |account|
      accounts_processed += 1
      account_updated = 0

      Patient.where(account_id: account.id, responsible_professional_id: nil)
             .where.not(contact_id: nil)
             .find_each(batch_size: 500) do |patient|
        first_event = AgendaEvent.where(account_id: account.id, contact_id: patient.contact_id)
                                  .where.not(user_id: nil)
                                  .order(:created_at)
                                  .first
        if first_event
          # update_column pula validations + callbacks pra ser rápido em massa.
          # Esta é uma data migration — não queremos disparar `after_update`
          # downstream em outros models.
          patient.update_column(:responsible_professional_id, first_event.user_id)
          account_updated += 1
        else
          total_skipped += 1
        end
      end

      total_updated += account_updated
      say "  Conta ##{account.id} (#{account.name}): #{account_updated} pacientes atualizados", :indent
    end

    say "Backfill concluído:"
    say "  Contas processadas:  #{accounts_processed}", :indent
    say "  Pacientes atualizados: #{total_updated}", :indent
    say "  Pacientes sem 1º agendamento (mantidos NULL): #{total_skipped}", :indent
    say "  Os mantidos NULL aparecerão como 'Sem profissional atribuído' na UI", :indent
    say "  e serão preenchidos automaticamente conforme a clínica criar plano,", :indent
    say "  agendar consulta, registrar sessão ou criar orçamento (callbacks).", :indent
  end

  def down
    # Reversão deliberadamente NÃO faz nada. Esta migration adiciona dados
    # úteis (atribuição de responsável); reverter seria perder informação
    # útil sem ganho — equivaleria a fingir que o paciente nunca teve um
    # dentista atendendo. Se necessário, faça UPDATE manual seletivo.
    say "down(): no-op intencional. Para reverter, use UPDATE manual com critério específico."
  end
end
