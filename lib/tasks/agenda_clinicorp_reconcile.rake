# PR-D parte 2 da limpeza Clinicorp (auditoria agendamento público §11):
# reconcilia retroativamente os AgendaEvents já importados aplicando a
# semântica correta das colunas `Canceled` e `Deleted` do XLSX Clinicorp +
# corrige status mal-mapeados (CHECKOUT, IN_SESSION, LATE).
#
# Contexto:
# Importação antes da PR-D parte 1 (importer fix) tinha 3 bugs:
#   1. `truthy?` não aceitava "X" → flags `Canceled=X`/`Deleted=X` viravam
#      false em `custom_attributes['clinicorp_canceled'/'clinicorp_deleted']`
#      e o evento entrava no Klivy como agendamento normal.
#   2. CHECKOUT/IN_SESSION/LATE caíam no fallback `scheduled`.
#   3. Canceled e Deleted eram tratados igual (ambos → status=cancelled),
#      perdendo a distinção semântica.
#
# Esta task lê o CSV original e aplica retroativamente em cada AgendaEvent
# `source=clinicorp` por `external_id`:
#   - `Canceled=X` → `status='cancelled'` + `clinicorp_canceled=true`
#                  + bump `updated_at` (lição aprendida do ETag stale)
#   - `Deleted=X`  → soft-delete (`deleted_at=NOW()`) + `clinicorp_deleted=true`
#                  + bump `updated_at`
#   - `Status` em CHECKOUT/IN_SESSION/LATE → aplica o STATUS_MAP corrigido
#
# Idempotente — flag `clinicorp_reconciled_at` em `custom_attributes` previne
# re-processamento.
#
# Reversível por soft-delete + custom_attributes preservados. Não dispara
# callbacks (usa `update_columns` em batch).
#
# Uso:
#
#   1) PREVIEW (sem aplicar):
#      bundle exec rails 'agenda_clinicorp:reconcile_canceled_deleted[31]'
#
#   2) APPLY (aplica e bump updated_at pra invalidar HTTP ETag cache):
#      bundle exec rails 'agenda_clinicorp:reconcile_canceled_deleted[31,plugins/xls/Appointment.csv,true]'
#
# Argumentos:
#   - account_id (obrigatório)
#   - csv_path (opcional, default: plugins/xls/Appointment.csv)
#   - apply (opcional, default: false — preview-only)
#
# Pré-requisito: PR-D parte 1 (importer) já em produção. Senão, próxima
# importação Clinicorp pode reintroduzir o mesmo problema.

require 'csv'

namespace :agenda_clinicorp do
  RECONCILE_FLAG = 'clinicorp_reconciled_at'.freeze

  # Espelha o STATUS_MAP corrigido em `clinicorp_agenda_importer.rb`. Mantém
  # duplicação aqui (em vez de require) pra evitar acoplamento da rake task
  # com o engine — só os 3 valores que precisam de fix retroativo bastam.
  RECONCILE_STATUS_MAP = {
    'CHECKOUT'   => 'completed',
    'IN_SESSION' => 'in_progress',
    'LATE'       => 'arrived'
  }.freeze

  desc 'PREVIEW/APPLY: reconcilia Canceled, Deleted e status mal-mapeados do XLSX Clinicorp'
  task :reconcile_canceled_deleted, [:account_id, :csv_path, :apply] => :environment do |_, args|
    account_id = args[:account_id].to_i
    csv_path   = args[:csv_path].presence || 'plugins/xls/Appointment.csv'
    apply      = args[:apply].to_s == 'true'

    if account_id.zero?
      warn 'Uso: rake agenda_clinicorp:reconcile_canceled_deleted[<account_id>,<csv_path>,<true|false>]'
      exit 1
    end

    account = Account.find_by(id: account_id)
    unless account
      warn "Conta #{account_id} não encontrada."
      exit 1
    end

    unless File.exist?(csv_path)
      warn "CSV não encontrado: #{csv_path}"
      exit 1
    end

    warn ''
    warn "=== Reconcile Clinicorp — #{apply ? 'APPLY' : 'PREVIEW'} — account_id=#{account_id} ==="
    warn "CSV: #{csv_path}"
    warn ''

    rows = parse_csv(csv_path)
    warn "Total de linhas no CSV: #{rows.size}"

    counters = Hash.new(0)
    samples = { canceled: [], deleted: [], status_fix: [] }
    now = Time.current

    rows.each do |row|
      external_id = row['id'].to_s.strip
      next if external_id.blank?

      canceled = truthy?(row['Canceled'])
      deleted  = truthy?(row['Deleted'])
      raw_status = row['Status'].to_s.strip.upcase
      remap_status = RECONCILE_STATUS_MAP[raw_status]

      next unless canceled || deleted || remap_status

      event = AgendaEvent.unscoped.where(account_id: account_id)
                         .where("custom_attributes->>'source' = ?", 'clinicorp')
                         .where("custom_attributes->>'external_id' = ?", external_id)
                         .first

      unless event
        counters[:not_found_in_db] += 1
        next
      end

      # Idempotência: pula eventos já reconciliados.
      if event.custom_attributes[RECONCILE_FLAG].present?
        counters[:already_reconciled] += 1
        next
      end

      attrs = event.custom_attributes.dup
      changes = {}

      if deleted
        # Deleted prevalece sobre Canceled (Clinicorp deleta após cancelar
        # quando o evento sai de vez do calendário).
        attrs['clinicorp_deleted'] = true
        changes[:deleted_at] = now unless event.deleted_at
        counters[:soft_deleted] += 1
        samples[:deleted] << event.id if samples[:deleted].size < 3
      elsif canceled
        attrs['clinicorp_canceled'] = true
        changes[:status] = 'cancelled' unless event.status == 'cancelled'
        counters[:status_set_cancelled] += 1
        samples[:canceled] << event.id if samples[:canceled].size < 3
      end

      if remap_status && event.status != remap_status && !deleted && !canceled
        # Só remap se NÃO houve Canceled/Deleted nesta linha — caso contrário
        # a flag tem precedência (clínica cancelou/deletou independente do
        # raw_status na hora).
        changes[:status] = remap_status
        attrs["clinicorp_status_remapped_from"] = event.status
        counters[:status_remapped] += 1
        counters["status_remapped_#{remap_status}".to_sym] += 1
        samples[:status_fix] << [event.id, event.status, remap_status] if samples[:status_fix].size < 3
      end

      attrs[RECONCILE_FLAG] = now.iso8601
      changes[:custom_attributes] = attrs
      changes[:updated_at] = now

      if apply
        event.update_columns(changes)
        counters[:events_updated] += 1
      else
        counters[:would_update] += 1
      end
    end

    warn ''
    warn '─' * 60
    counters.each { |k, v| warn format('  %-30s %s', k, v) }
    warn '─' * 60

    if samples[:canceled].any?
      warn ''
      warn "Amostra canceled: event_ids=#{samples[:canceled].inspect}"
    end
    if samples[:deleted].any?
      warn "Amostra deleted: event_ids=#{samples[:deleted].inspect}"
    end
    if samples[:status_fix].any?
      warn "Amostra status_fix: #{samples[:status_fix].map { |a| "id=#{a[0]} #{a[1]}→#{a[2]}" }.inspect}"
    end

    warn ''
    warn(apply ? '✅ Reconciliação APLICADA.' : '🟡 PREVIEW — rode com `[<account_id>,<csv_path>,true]` para aplicar.')
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def parse_csv(path)
    content = File.read(path)
    content = content.sub(/\A\xEF\xBB\xBF/, '') # strip BOM
    delim = %w[, ;].max_by { |d| content.lines.first.to_s.count(d) }
    CSV.parse(content, headers: true, col_sep: delim, liberal_parsing: true).map(&:to_h)
  end

  # Mesmo critério do importer pós-PR-D (aceita "X" / "x").
  def truthy?(val)
    %w[true 1 yes sim t x].include?(val.to_s.strip.downcase)
  end
end
