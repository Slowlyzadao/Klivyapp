# PR-UX-3 (auditoria UX 2026-05-15): popula `PatientAppointment` para todos
# os AgendaEvents Clinicorp que ainda não têm registro correspondente.
#
# Motivação: o importer histórico (`clinicorp_agenda_importer`) criou
# AgendaEvent + Patient + Contact, mas NÃO criou PatientAppointment.
# Resultado: prontuário do paciente (aba "Meus Agendamentos") fica vazio
# para todo histórico Clinicorp; timeline clínica e relatórios baseados
# em PatientAppointment ignoram esses eventos.
#
# Estratégia:
#   - A2 (decisão de produto 2026-05-15): primeiro evento cronológico de
#     cada paciente = `appointment_type='avaliacao'`; restante = `'retorno'`.
#     Ordenação é feita em batch (ordena por starts_at por contact_id),
#     então o resultado é correto mesmo se o XLS original veio
#     fora de ordem.
#   - B1: pula AgendaEvents soft-deletados (`deleted_at IS NOT NULL`) —
#     evento que a clínica apagou no Clinicorp não deveria aparecer no
#     prontuário do paciente.
#   - Idempotente: pula AgendaEvents que já têm PatientAppointment via
#     `agenda_event_id` (segura re-execução).
#
# Sub-tasks:
#   - `agenda_clinicorp:backfill_appointments_preview[<account_id>]`
#   - `agenda_clinicorp:backfill_appointments_apply[<account_id>]`
#
# Idempotente — re-rodar é seguro (eventos já com PatientAppointment são
# pulados).

namespace :agenda_clinicorp do
  # Mesmo mapping usado pelo importer pós PR-UX-3.
  APPT_STATUS_MAP_BACKFILL = {
    'scheduled'   => 'scheduled',
    'confirmed'   => 'scheduled',
    'arrived'     => 'scheduled',
    'in_progress' => 'scheduled',
    'completed'   => 'done',
    'no_show'     => 'no_show',
    'cancelled'   => 'canceled'
  }.freeze

  desc 'PREVIEW: conta o que seria criado pelo backfill de PatientAppointments'
  task :backfill_appointments_preview, [:account_id] => :environment do |_, args|
    run_appointments_backfill(account_id: args[:account_id].to_i, apply: false)
  end

  desc 'APPLY: cria PatientAppointment para todos AgendaEvents Clinicorp kept que não têm um'
  task :backfill_appointments_apply, [:account_id] => :environment do |_, args|
    run_appointments_backfill(account_id: args[:account_id].to_i, apply: true)
  end

  def run_appointments_backfill(account_id:, apply:)
    if account_id.zero?
      warn 'Uso: rake agenda_clinicorp:backfill_appointments_preview[<account_id>] (ou _apply)'
      exit 1
    end

    account = Account.find_by(id: account_id)
    unless account
      warn "Conta #{account_id} não encontrada."
      exit 1
    end

    mode = apply ? 'APPLY' : 'PREVIEW'
    warn ''
    warn "=== Backfill PatientAppointments Clinicorp — #{mode} — account_id=#{account_id} ==="
    warn ''

    # 1) Pega AgendaEvents Clinicorp kept (B1: skipa soft-deletados).
    events = AgendaEvent.kept
                        .where(account_id: account_id)
                        .where("custom_attributes->>'source' = ?", 'clinicorp')
                        .where.not(contact_id: nil)
                        .order(:starts_at)
                        .to_a

    warn "AgendaEvents Clinicorp kept com contact_id: #{events.size}"

    # 2) Pega AgendaEvents que JÁ têm PatientAppointment (pra pular).
    existing_ids = PatientAppointment.where(account_id: account_id)
                                     .where.not(agenda_event_id: nil)
                                     .pluck(:agenda_event_id).to_set
    warn "AgendaEvents que já têm PatientAppointment: #{existing_ids.size}"

    # 3) Mapeia contact_id → patient_id (1 query).
    patients_by_contact = Patient.active
                                 .where(account_id: account_id)
                                 .where.not(contact_id: nil)
                                 .pluck(:contact_id, :id).to_h
    warn "Patients vinculados a contacts: #{patients_by_contact.size}"

    # 4) Determina, em batch, quem é "primeiro evento" por contact (A2).
    # Como events já está ordenado por starts_at, primeiro evento por
    # contact_id = o que aparece primeiro no loop.
    first_event_id_by_contact = {}
    events.each do |e|
      first_event_id_by_contact[e.contact_id] ||= e.id
    end

    counters = Hash.new(0)
    samples = []

    events.each do |event|
      if existing_ids.include?(event.id)
        counters[:already_exists] += 1
        next
      end

      patient_id = patients_by_contact[event.contact_id]
      unless patient_id
        counters[:patient_not_found] += 1
        next
      end

      appointment_type = (first_event_id_by_contact[event.contact_id] == event.id) ? 'avaliacao' : 'retorno'
      status           = APPT_STATUS_MAP_BACKFILL[event.status.to_s] || 'scheduled'
      duration         = ((event.ends_at - event.starts_at) / 60).to_i
      duration         = 60 if duration <= 0

      counters["created_#{appointment_type}".to_sym] += 1
      counters["status_#{status}".to_sym] += 1
      counters[:would_create] += 1

      if samples.size < 3
        samples << {
          event_id: event.id, patient_id: patient_id,
          type: appointment_type, status: status,
          scheduled_at: event.starts_at.strftime('%d/%m/%Y %H:%M')
        }
      end

      next unless apply

      PatientAppointment.create!(
        account_id: account_id,
        patient_id: patient_id,
        professional_id: event.user_id,
        agenda_event_id: event.id,
        appointment_type: appointment_type,
        status: status,
        scheduled_at: event.starts_at,
        ends_at: event.ends_at,
        duration_minutes: duration
      )
      counters[:created] += 1
    end

    warn ''
    warn '─' * 60
    counters.sort.each { |k, v| warn format('  %-30s %s', k, v) }
    warn '─' * 60

    if samples.any?
      warn ''
      warn '=== Amostra de 3 ==='
      samples.each_with_index do |s, i|
        warn "[#{i + 1}] event=#{s[:event_id]} patient=#{s[:patient_id]} " \
             "type=#{s[:type]} status=#{s[:status]} at=#{s[:scheduled_at]}"
      end
    end

    warn ''
    warn(apply ? '✅ Backfill APLICADO.' : '🟡 Rode `_apply` para aplicar.')
  end
end
