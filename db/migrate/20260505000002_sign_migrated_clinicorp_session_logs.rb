class SignMigratedClinicorpSessionLogs < ActiveRecord::Migration[7.0]
  # Backfill: SessionLogs criados pelo `ClinicorpTreatmentOperationImporter` em
  # [1.5.3.0] vieram como `draft` por excesso de conservadorismo. Como esses
  # procedimentos JÁ aconteceram (data de 2019-2026) e já foram implicitamente
  # assinados pelo profissional no Clinicorp, marcá-los como `draft` em 2026:
  #   - confunde UX ("Rascunho" em registro de 2 anos atrás)
  #   - viola regulação CFO (prontuário deve ser assinado)
  #   - cai pra fora da janela de 48h, virando "rascunho zumbi" (não-editável,
  #     não-assinado, sem caminho na UI normal pra resolver)
  #
  # Migração faz sentido conceitual de "este procedimento foi executado,
  # registrado e implicitamente assinado pelo profissional X em Y data,
  # importado do Clinicorp":
  #
  #   status      → 'signed'
  #   signed_by   → professional_id (o dentista que executou)
  #   signed_at   → performed_at    (assinatura concorrente ao ato)
  #
  # Pula registros sem professional_id (1 caso: linha do XLSX sem dentista
  # identificável) — não tem como assinar sem signer válido.
  #
  # Usa `update_all` (raw SQL) pra:
  #   1. Bypassar `prevent_edit_if_signed` (que veta updates em signed mas o
  #      callback só roda em update via AR — update_all vai direto pro banco).
  #   2. Não disparar `record_timeline_session_signed` (8596 timeline events
  #      retroativos polui a aba Timeline do paciente).
  #   3. Velocidade: 1 UPDATE em vez de 8596 round-trips.
  #
  # Idempotente: filtra por `status = 'draft'` AND `external_ids` tem
  # `clinicorp_operation_id`. 2ª execução: WHERE não casa nada → 0 rows.
  def up
    affected = SessionLog.where(status: 'draft')
                         .where("external_ids -> 'clinicorp_operation_id' IS NOT NULL")
                         .where.not(professional_id: nil)
                         .update_all(<<~SQL.squish)
                           status = 'signed',
                           signed_by_id = professional_id,
                           signed_at = performed_at,
                           updated_at = NOW()
                         SQL

    say_with_time "Sessões migradas marcadas como signed: #{affected}", &-> {}
  end

  def down
    # Reverte SessionLogs migrados de volta pra draft. Idempotente.
    SessionLog.where(status: 'signed')
              .where("external_ids -> 'clinicorp_operation_id' IS NOT NULL")
              .update_all(<<~SQL.squish)
                status = 'draft',
                signed_by_id = NULL,
                signed_at = NULL,
                updated_at = NOW()
              SQL
  end
end
