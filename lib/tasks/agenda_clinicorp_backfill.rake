# PR-C da limpeza do catálogo Clinicorp (auditoria agendamento público §11):
# transforma os AgendaEvents importados da Clinicorp para o novo padrão de
# campos que a PR-B passou a usar nas importações futuras:
#
#   ANTES (importer pré-PR-B):
#     - description       = Notes (texto livre da secretária)
#     - agenda_service_id = service criado a partir de Procedures (poluindo
#                           o catálogo com 2.046 services-anotação)
#     - custom_attributes["treatment"] = nome do service
#
#   DEPOIS (importer pós-PR-B + este backfill):
#     - description                     = Procedures (movido do nome do service)
#     - agenda_service_id               = NULL (exceto se vinculado a um service
#                                         protegido — com treatment_items > 0)
#     - custom_attributes[attr_categoria] = (sem alteração, já existe)
#     - custom_attributes[attr_notas]   = Notes (movido do description)
#     - custom_attributes["treatment"]  = NULL
#
# Esta task tem 2 sub-tasks:
#
#   1) `agenda_clinicorp:backfill_preview[<account_id>]`
#      Conta o que SERIA alterado. Não toca no banco. Imprime sumário e exemplos.
#
#   2) `agenda_clinicorp:backfill_apply[<account_id>]`
#      Aplica as mudanças. Idempotente — eventos já com `clinicorp_backfilled_at`
#      em `custom_attributes` são pulados (rodar 2× é seguro).
#
# Reversibilidade:
#   - Eventos: cada `update_columns` toca campos específicos; um script de undo
#     pode percorrer `custom_attributes["source"]=clinicorp` E `backfilled_at`
#     presente, e mover de volta Notes para description (zerando o attr_notas).
#   - Services: soft-delete (`deleted_at`) — reversível com
#     `AgendaService.discarded.update_all(deleted_at: nil)`.
#
# Proteções hard-rule (não negociáveis):
#   - NÃO toca em eventos com `custom_attributes["source"] != "clinicorp"`.
#     Booking público (`source: public_booking`) e eventos manuais ficam intactos.
#   - NÃO arquiva services com `treatment_items.count > 0` mesmo se a heurística
#     da PR-A sugeriu arquivar. Plano de tratamento usa esses services.
#
# Pré-requisito: PR-B (importer fix) já em produção. Senão, nova importação
# Clinicorp recria o lixo durante a janela entre PR-C apply e PR-B deploy.

namespace :agenda_clinicorp do
  NOTES_ATTR_NAME = 'Notas (Clinicorp)'.freeze
  BACKFILL_FLAG   = 'clinicorp_backfilled_at'.freeze

  desc 'PREVIEW: conta o que seria alterado pelo backfill Clinicorp (não altera nada)'
  task :backfill_preview, [:account_id] => :environment do |_, args|
    run_backfill(account_id: args[:account_id].to_i, apply: false)
  end

  desc 'APPLY: aplica backfill Clinicorp (mover Notes→custom attr, Procedures→description, soft-delete services não-protegidos)'
  task :backfill_apply, [:account_id] => :environment do |_, args|
    run_backfill(account_id: args[:account_id].to_i, apply: true)
  end

  # Bugfix 2026-05-15: backfill original limpou `treatment` em custom_attributes,
  # mas esqueceu `service_id` e `service_name`. Frontend usa `service_name`
  # como fallback para mostrar "tratamento" no card do evento — chaves stale
  # = UI continuava exibindo o nome do service arquivado. Esta task remove
  # essas 3 chaves dos eventos já backfillados cujo `agenda_service_id` agora
  # é nil (eventos protegidos com FK preservada ficam intactos).
  desc 'CLEANUP: remove service_id/service_name stale de custom_attributes (bugfix do backfill anterior)'
  task :backfill_cleanup_stale_keys, [:account_id, :apply] => :environment do |_, args|
    account_id = args[:account_id].to_i
    apply = args[:apply].to_s == 'true'
    if account_id.zero?
      warn 'Uso: rake agenda_clinicorp:backfill_cleanup_stale_keys[<account_id>,true]'
      exit 1
    end

    scope = AgendaEvent.where(account_id: account_id)
                       .where("custom_attributes->>'source' = ?", 'clinicorp')
                       .where("(custom_attributes->>'#{BACKFILL_FLAG}') IS NOT NULL")
                       .where(agenda_service_id: nil) # só os "desvinculados"
                       .where("custom_attributes ? 'service_name' OR custom_attributes ? 'service_id' OR custom_attributes ? 'treatment'")

    total = scope.count
    warn "=== Cleanup stale keys — account_id=#{account_id} — #{apply ? 'APPLY' : 'PREVIEW'} ==="
    warn "Eventos com chaves stale a limpar: #{total}"

    # `return` dentro de bloco de Rake gera LocalJumpError. Estrutura com if
    # bloqueia o resto da task quando não é apply.
    if apply
      updated = 0
      scope.find_each(batch_size: 500) do |e|
        attrs = e.custom_attributes.dup
        removed = false
        %w[service_id service_name treatment].each do |k|
          if attrs.key?(k)
            attrs.delete(k)
            removed = true
          end
        end
        next unless removed
        e.update_columns(custom_attributes: attrs)
        updated += 1
      end
      warn "Eventos atualizados: #{updated}"
    else
      warn '🟡 PREVIEW — rode com `[<account_id>,true]` para aplicar.'
    end
  end

  def run_backfill(account_id:, apply:)
    if account_id.zero?
      warn 'Uso: rake agenda_clinicorp:backfill_preview[<account_id>] (ou backfill_apply)'
      exit 1
    end

    account = Account.find_by(id: account_id)
    if account.nil?
      warn "Conta #{account_id} não encontrada."
      exit 1
    end

    mode = apply ? 'APPLY' : 'PREVIEW'
    warn ''
    warn "=== Backfill Clinicorp — #{mode} — account_id=#{account_id} (#{account.name}) ==="
    warn ''

    # 1) Garante o custom attribute "Notas (Clinicorp)" — só cria em apply.
    notes_attr = find_or_create_notes_attr(account_id, apply: apply)
    notes_attr_id = notes_attr&.id
    warn "Custom attribute '#{NOTES_ATTR_NAME}' #{apply ? 'pronto' : '(seria criado)'}: id=#{notes_attr_id.inspect}"

    # 2) IDs de services protegidos por treatment_items.
    protected_ids = TreatmentItem.where(account_id: account_id)
                                 .where.not(agenda_service_id: nil)
                                 .distinct.pluck(:agenda_service_id)
    warn "Services protegidos (treatment_items > 0): #{protected_ids.inspect}"
    warn ''

    # 3) Iterar AgendaEvents da importação Clinicorp.
    events_scope = AgendaEvent.where(account_id: account_id)
                              .where("custom_attributes->>'source' = ?", 'clinicorp')
                              .where("(custom_attributes->>'#{BACKFILL_FLAG}') IS NULL")

    counters = Hash.new(0)
    counters[:events_total] = events_scope.count
    sample_events = []

    events_scope.find_each(batch_size: 500) do |event|
      result = transform_event(event, protected_ids, notes_attr_id, apply: apply)
      counters[result[:bucket]] += 1
      sample_events << result[:preview] if sample_events.size < 3 && result[:preview]
    end

    # 4) Soft-delete dos services não protegidos.
    services_scope = AgendaService.where(account_id: account_id).kept
                                  .where.not(id: protected_ids)
    counters[:services_to_archive] = services_scope.count

    if apply
      now = Time.current
      counters[:services_archived] = services_scope.update_all(deleted_at: now)
    end

    # 5) Relatório.
    warn '─' * 60
    counters.each { |k, v| warn format('  %-30s %s', k, v) }
    warn '─' * 60

    if sample_events.any?
      warn ''
      warn '=== Amostra de 3 transformações ==='
      sample_events.each_with_index do |s, i|
        warn ''
        warn "[Evento #{i + 1}] id=#{s[:id]}"
        warn "  ANTES:  description=#{s[:before_desc].inspect.truncate(80)}"
        warn "          agenda_service_id=#{s[:before_svc]}"
        warn "  DEPOIS: description=#{s[:after_desc].inspect.truncate(80)}"
        warn "          agenda_service_id=#{s[:after_svc]}"
        warn "          notes_attr=#{s[:notes_value].to_s.inspect.truncate(80)}"
      end
    end

    warn ''
    warn(apply ? '✅ Backfill APLICADO.' : '🟡 Rode `backfill_apply` para aplicar de verdade.')
  end

  def find_or_create_notes_attr(account_id, apply:)
    existing = AgendaCustomAttribute.where(account_id: account_id)
                                    .where('LOWER(name) = ?', NOTES_ATTR_NAME.downcase).first
    return existing if existing
    return nil unless apply

    AgendaCustomAttribute.create!(
      account_id: account_id,
      name: NOTES_ATTR_NAME,
      field_type: 'textarea',
      required: false,
      position: AgendaCustomAttribute.where(account_id: account_id).count
    )
  end

  # Transforma um único evento. Retorna `{ bucket: <símbolo>, preview: {...}? }`.
  # `bucket` agrupa o resultado para o relatório (events_updated, events_protected,
  # events_no_change). `preview` é setado só para os 3 primeiros, pra ilustrar.
  def transform_event(event, protected_ids, notes_attr_id, apply:)
    before_desc = event.description
    before_svc  = event.agenda_service_id
    attrs       = (event.custom_attributes || {}).dup

    # 3a) Notes (description atual) → attr_<notas_id>.
    notes_value = before_desc.to_s.strip.presence

    # 3b) Procedures (nome do service) → description, se service NÃO é protegido.
    if before_svc.present? && !protected_ids.include?(before_svc)
      svc = AgendaService.find_by(id: before_svc)
      new_desc = svc&.name
      new_svc  = nil
    else
      # Service protegido (mantém id) OU sem service: description fica vazio.
      new_desc = nil
      new_svc  = before_svc
    end

    attrs["attr_#{notes_attr_id}"] = notes_value if notes_value && notes_attr_id
    # PR-C bugfix 2026-05-15: além de `treatment`, o importer original também
    # salvava `service_id` e `service_name` em custom_attributes (espelho do
    # FK). O frontend lê `service_name` para exibir o "tratamento" no card —
    # se essas chaves ficam stale, UI segue mostrando o nome do service-anotação
    # mesmo com `agenda_service_id=nil`. Limpa as 3 chaves para eventos cujo
    # service vai ser arquivado.
    unless protected_ids.include?(before_svc)
      attrs['treatment']    = nil
      attrs['service_id']   = nil
      attrs['service_name'] = nil
    end
    attrs[BACKFILL_FLAG]           = Time.current.iso8601

    if apply
      event.update_columns(
        description: new_desc,
        agenda_service_id: new_svc,
        custom_attributes: attrs
      )
    end

    bucket = if before_svc && protected_ids.include?(before_svc)
               :events_protected_service
             elsif before_svc
               :events_service_archived
             else
               :events_no_service
             end

    {
      bucket: bucket,
      preview: {
        id: event.id,
        before_desc: before_desc,
        before_svc: before_svc,
        after_desc: new_desc,
        after_svc: new_svc,
        notes_value: notes_value
      }
    }
  end
end
