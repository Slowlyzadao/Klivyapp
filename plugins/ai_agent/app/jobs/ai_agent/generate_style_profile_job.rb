# Projeto "Tom de voz da Bea" — Fase 2 (geração).
#
# Roda a destilação do tom de voz da conta (AiAgent::StyleProfile::Distiller)
# em background e persiste o resultado no RASCUNHO (style_profile_draft) do
# AccountSetting — o perfil ATIVO (style_profile) não é tocado: regerar não
# derruba a voz ao vivo. A aprovação (copiar rascunho → ativo) é à parte (Fase 3).
#
# Status do rascunho alimenta a UI: generating → ready | failed. Marcar status
# PRESERVA o conteúdo anterior do rascunho (merge) — uma regeração que falha
# não apaga um rascunho bom já existente.
class AiAgent::GenerateStyleProfileJob < ApplicationJob
  queue_as :low

  # Geração rodou mas não extraiu nenhum traço útil (IA devolveu vazio / erro
  # definitivo de billing-auth nos dois modelos). Vira 'failed' acionável em vez
  # de um rascunho 'ready' enganosamente vazio.
  class EmptyProfile < StandardError; end

  def perform(account_id)
    account = ::Account.find_by(id: account_id)
    return if account.nil?

    # find_or_create_by! (não create_or_find_by!): o model valida unicidade de
    # account_id, então create_or_find_by! estouraria RecordInvalid no caso comum
    # (setting já existe) antes de cair no find. Mesma convenção do resto do plugin.
    @setting = ::AiAgent::AccountSetting.find_or_create_by!(account_id: account.id)
    # started_at carimba o início — deixa o controller detectar um 'generating'
    # órfão (worker morto antes do status terminal) como stale e permitir regerar.
    mark_status('generating', 'started_at' => Time.current.iso8601)
    @setting.update!(style_profile_draft: distill(account).merge('status' => 'ready'))
  rescue ::AiAgent::StyleProfile::Distiller::InsufficientData => e
    # Determinístico (sem dado): marca failed e NÃO retenta.
    mark_status('failed', 'error' => e.message)
  rescue EmptyProfile
    mark_status('failed', 'error' => 'Não consegui extrair um tom de voz das conversas ' \
                                     '(IA indisponível ou sem texto útil). Tente novamente.')
  rescue StandardError => e
    Rails.logger.error("[AiAgent::GenerateStyleProfileJob] #{e.class}: #{e.message}")
    mark_status('failed', 'error' => 'Falha ao gerar o tom de voz. Tente novamente.')
    raise
  end

  private

  # Roda a destilação e devolve o perfil, ou levanta: UNAVAILABLE (LLM esgotado)
  # → re-tenta no Sidekiq; EmptyProfile (rodou mas sem traço útil) → failed.
  def distill(account)
    profile = ::AiAgent::StyleProfile::Distiller.call(account: account)
    if profile == ::AiAgent::Training::LlmResilience::UNAVAILABLE
      raise 'Geração do tom de voz indisponível (rate-limit/crédito da IA). ' \
            'Será reprocessada automaticamente quando o limite liberar.'
    end
    raise EmptyProfile if blank_profile?(profile)

    profile
  end

  # Perfil sem nenhum traço qualitativo (summary/greeting/closing/expressions/
  # examples) é inútil — emojis sozinhos não contam.
  def blank_profile?(profile)
    return true unless profile.is_a?(Hash)

    has_text = [profile['summary'], profile['greeting'], profile['closing']].any? { |v| v.to_s.strip.present? }
    has_list = Array(profile['expressions']).any? || Array(profile['examples']).any?
    !(has_text || has_list)
  end

  # Marca o status preservando o conteúdo anterior do rascunho (merge).
  def mark_status(status, extra = {})
    return if @setting.nil?

    @setting.update!(style_profile_draft: @setting.style_profile_draft.to_h.merge('status' => status).merge(extra))
  end
end
