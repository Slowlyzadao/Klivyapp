# Adiciona o contato atual à LISTA DE ESPERA reutilizando o model
# WaitingListEntry do plugin agenda (upsert por contact_id) — não cria
# nada novo no agenda, só consome o que já existe. Usada nos passos
# 2.3/2.4/2.5 do fluxo BIA (sem horário, disponibilidade distante, ou
# recusa do profissional alternativo). Ver docs/04-ai-agent/clean-architecture.md (§4).
class AiAgent::Tools::AddToWaitingListTool < AiAgent::Tools::BaseTool
  PERIOD_MAP = {
    'manha' => 'morning', 'manhã' => 'morning', 'morning' => 'morning',
    'tarde' => 'afternoon', 'afternoon' => 'afternoon',
    'noite' => 'evening', 'evening' => 'evening'
  }.freeze
  VALID_DAYS = %w[seg ter qua qui sex sab dom].freeze

  description <<~DESC
    Adiciona o paciente à LISTA DE ESPERA da clínica, para ser chamado
    quando abrir vaga. Use quando não há horário disponível, a
    disponibilidade é distante (> 1 mês), ou o paciente recusa as
    opções — e SÓ depois de ele CONFIRMAR que quer entrar na lista.
  DESC

  param :period,
        type: :string,
        desc: 'Período de preferência: "morning" (manhã), "afternoon" (tarde) ou "evening" (noite). Obrigatório.'

  param :preferred_days,
        type: :string,
        required: false,
        desc: 'Dias de preferência separados por vírgula, em minúsculas de 3 letras (seg,ter,qua,qui,sex,sab,dom). Opcional.'

  param :specific_time,
        type: :string,
        required: false,
        desc: 'Horário específico no formato HH:MM. Opcional — se omitido, qualquer horário no período.'

  param :notes,
        type: :string,
        required: false,
        desc: 'Observações livres do paciente (ex: "só depois das 9h"). Opcional.'

  def execute(period:, preferred_days: nil, specific_time: nil, notes: nil)
    return { added: false, error: 'Módulo de agenda não disponível.' } unless defined?(::WaitingListEntry)
    return { added: false, error: 'Sem contato vinculado a esta conversa.' } if contact_id.blank?

    mapped = PERIOD_MAP[period.to_s.strip.downcase]
    return { added: false, error: 'Período inválido. Use morning, afternoon ou evening.' } if mapped.nil?

    days = preferred_days.to_s.downcase.split(/[,\s]+/).map(&:strip).select { |d| VALID_DAYS.include?(d) }

    entry = ::WaitingListEntry.find_or_initialize_by(account_id: account.id, contact_id: contact_id)
    entry.period = mapped
    entry.preferred_days = days if days.any?
    entry.specific_time = specific_time.presence
    entry.notes = notes.presence
    entry.save!

    patient_memory&.append_history(
      event_type: 'waiting_list_added',
      summary: "Entrou na lista de espera (período: #{mapped})",
      metadata: { waiting_list_entry_id: entry.id }
    )

    {
      added: true,
      entry: { id: entry.id, period: mapped, preferred_days: days, specific_time: entry.specific_time },
      note_for_bea: 'Paciente entrou na lista de espera. Avise que a clínica chama assim que abrir vaga, confirme dúvidas e pergunte como ele conheceu a clínica.'
    }
  rescue ActiveRecord::RecordInvalid => e
    { added: false, error: e.message }
  end
end
