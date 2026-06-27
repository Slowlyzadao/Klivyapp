# Assembles the system instructions sent to the LLM. Three layers:
#
#   1. Persona base (from the account's persona template, or a sane default
#      tuned for clinics)
#   2. Account-specific prefix (super admin field on AccountSetting)
#   3. Patient memory snapshot (preferences, last few history entries)
#
# Conversation history (the back-and-forth turns) is added separately to
# the chat object — not here.
class AiAgent::PromptBuilder
  # Super admin can override the persona block globally via this
  # InstallationConfig key. When set, takes precedence over the persona
  # template attached to the account and over DEFAULT_PERSONA_PROMPT.
  GLOBAL_PROMPT_CONFIG_KEY = 'CAPTAIN_BEA_SYSTEM_PROMPT'.freeze

  DEFAULT_PERSONA_PROMPT = <<~PT.strip
    Você é a Bea, assistente virtual de uma clínica. Seu papel é atender
    pacientes com naturalidade, empatia e precisão. Diretrizes:

    - Fale em português do Brasil, em tom acolhedor e profissional.
    - Use o termo "paciente" (não "cliente").

    Ordem de busca de informação (NUNCA INVENTE):
      1. Para horários de funcionamento, lista de serviços, duração e preço
         dos procedimentos, feriados e regras gerais → use SEMPRE `clinic_info`.
      2. Para políticas internas, FAQs e textos institucionais (que não são
         horários nem catálogo de serviços) → use `search_knowledge`.
      3. Para dados do paciente atual (nome, alergias, profissional
         responsável) → use `patient_lookup`.
      4. Para consultas já marcadas → use `list_appointments`.
      5. Para situação financeira → use `financial_status`.

    Agendamento:
      - Quando o paciente pedir para marcar, SEMPRE chame `clinic_info`
        antes para confirmar horário de funcionamento e duração do serviço.
      - Confirme com o paciente data, hora e tipo antes de chamar
        `book_appointment`. Use ISO8601 com timezone -03:00 (Brasil).
      - Após agendar, repita os dados ao paciente para ele conferir.

    Hand-off:
      - Se o paciente demonstrar frustração persistente, pedir humano,
        ou tocar em tema sensível (reclamação, cobrança, dor forte),
        chame `transfer_to_human` imediatamente.

    Limites:
      - Não dê diagnósticos médicos nem prescrições.
      - Não negocie descontos ou prazos por conta própria.

    Estilo:
      - Respostas curtas (3 frases no máximo). Use até 1 emoji.
  PT

  def initialize(account:, conversation_state:, patient_memory: nil, contact: nil)
    @account = account
    @resolver = AiAgent::ConfigResolver.new(account)
    @conversation_state = conversation_state
    @patient_memory = patient_memory
    @contact = contact
  end

  def system_instructions
    [
      persona_block,
      beatriz_assistant_block,
      style_block,
      responsible_physician_block,
      account_prefix_block,
      contact_identity_block,
      patient_memory_block,
      state_block
    ].compact.join("\n\n---\n\n")
  end

  # Default global do super admin: o override do InstallationConfig (o que se
  # edita em /super_admin/bea). Fonte ÚNICA usada tanto pelo persona_block
  # (fallback de runtime) quanto pelo SystemPromptsController (botão "Restaurar
  # padrão"), pra os dois nunca divergirem. `persona` opcional só pro fallback.
  def self.global_default_prompt(persona: nil)
    override = InstallationConfig.find_by(name: GLOBAL_PROMPT_CONFIG_KEY)&.value.to_s.strip
    return override if override.present?

    persona&.system_prompt.presence || DEFAULT_PERSONA_PROMPT
  end

  private

  # Precedência: system message PRÓPRIO da conta → default global do super admin
  # → persona template → fallback embutido. Account-first é o que dá a cada
  # clínica o seu prompt (congelado); só cai no default global quando a conta
  # ainda não tem o seu (conta nova ou que limpou o campo) — a Bea nunca roda
  # sem prompt.
  def persona_block
    account_prompt = @resolver.system_prompt.to_s.strip
    return account_prompt if account_prompt.present?

    self.class.global_default_prompt(persona: @resolver.persona)
  end

  # MVP lançamento: fluxo do voucher (comemora + agenda; troca de procedimento
  # → encaminha pro humano e para). Injetado só quando a conta está em modo
  # voucher. NÃO mexe na persona global.
  VOUCHER_FLOW = <<~PT.strip
    FLUXO DE LANÇAMENTO (VOUCHER) — prioritário nesta conversa: esta paciente
    chegou por um VOUCHER de desconto de um lançamento.
    1. Quando ela mandar/contar o voucher, COMEMORE de forma calorosa o que ela
       ganhou (ex.: "Aii que delícia, você ganhou X!") e já convide pra agendar
       o procedimento do voucher.
    2. Conduza o agendamento normalmente do procedimento do voucher.
    3. NÃO precisa informar nem confirmar o valor/desconto — a recepção aplica o
       desconto no atendimento. Só comemore e agende.
    4. Se a paciente quiser TROCAR por um procedimento DIFERENTE do voucher (ex.:
       "não quero esse, queria outra coisa"): diga com carinho que vai verificar
       com a Sabrina o que dá pra fazer ("deixa eu dar uma olhada e falar com a
       Sabrina pra ver o que a gente consegue, tá?") e PERGUNTE qual procedimento
       ela gostaria. ASSIM QUE ela disser o procedimento, chame a ferramenta
       transfer_to_human e NÃO responda mais — a equipe assume daqui. NUNCA
       prometa desconto em outro procedimento.
  PT

  def account_prefix_block
    parts = []
    prefix = @resolver.system_prompt_prefix
    parts << prefix if prefix.present?
    parts << VOUCHER_FLOW if @resolver.voucher_mode?
    return nil if parts.empty?

    "Instruções específicas desta clínica:\n#{parts.join("\n\n")}"
  end

  # Tom de voz da clínica (projeto de estilo): perfil destilado das conversas
  # reais — emoji, saudação, bordões, exemplos. Camada de SUPERFÍCIE: muda só
  # COMO a Bea fala, nunca O QUE ela pode dizer. Vem DEPOIS da persona (que
  # carrega os limites e a ordem de busca de fatos) de propósito. Retorna nil
  # quando a conta não tem perfil ativo.
  def style_block
    AiAgent::StyleProfile::PromptSection.for_account(@account)
  end

  # Pulls the per-account Beatriz config from the Captain::Assistant row
  # (see Settings.vue → "Sobre a clínica" + system messages). This is the
  # bridge between the user-facing assistant settings page and the actual
  # LLM prompt — without this block, what the user types there is invisible
  # to Bea.
  def beatriz_assistant_block
    return nil unless defined?(::Captain::Assistant)

    assistant = ::Captain::Assistant.where(account_id: @account.id, name: 'Beatriz').first
    return nil if assistant.nil?

    lines = []

    desc = assistant.description.to_s.strip
    lines << "Sobre você: #{desc}" if desc.present?

    profile = assistant.config['clinic_profile'].is_a?(Hash) ? assistant.config['clinic_profile'] : {}
    profile_lines = []
    profile_lines << "  Nome da clínica: #{profile['name']}" if profile['name'].to_s.strip.present?
    profile_lines << "  Endereço: #{profile['address']}"     if profile['address'].to_s.strip.present?

    hours_line = format_business_hours
    profile_lines << "  Horário de atendimento: #{hours_line}" if hours_line.present?

    services_line = format_services
    profile_lines << "  Serviços oferecidos: #{services_line}" if services_line.present?

    if profile_lines.any?
      lines << 'Dados da clínica (use estes valores quando o paciente perguntar — NUNCA invente):'
      lines.concat(profile_lines)
    end

    handoff = assistant.config['handoff_message'].to_s.strip
    resolution = assistant.config['resolution_message'].to_s.strip
    if handoff.present? || resolution.present?
      lines << 'Mensagens da clínica:'
      lines << "  Use ao transferir para humano: \"#{handoff}\""    if handoff.present?
      lines << "  Use ao encerrar a conversa: \"#{resolution}\""    if resolution.present?
    end

    return nil if lines.empty?

    lines.join("\n")
  end

  # Médico (ou profissional do conselho equivalente) responsável técnico
  # pela clínica. CFM 2.454/2026 exige menção identificável em qualquer
  # atendimento mediado por IA. Aparece na assinatura virtual da Bea
  # quando o paciente perguntar quem é o(a) responsável.
  def responsible_physician_block
    setting = AiAgent::AccountSetting.find_by(account_id: @account.id)
    return nil if setting.nil?

    user = setting.responsible_physician
    return nil if user.nil?

    council = setting.responsible_physician_council.to_s.strip
    crm = setting.responsible_physician_crm.to_s.strip
    identifier = [council.presence, crm.presence].compact.join(' ')

    lines = ['Responsável técnico desta clínica:']
    lines << "  Nome: #{user.name}"
    lines << "  Conselho: #{identifier}" if identifier.present?
    lines << '  Quando o paciente perguntar quem é o(a) responsável, médica responsável, ou pedir contato/CRM, use estes dados. Não invente outros nomes nem números.'
    lines.join("\n")
  end

  # Injeta a identidade do contato (vinda do pushName do WhatsApp) no
  # contexto da Bea. Sem isso o LLM alucina nomes quando tenta soar
  # cordial. Se o pushName for confiável (parece um nome real, sem
  # emojis/símbolos), instrui a usar o primeiro nome; senão, instrui
  # a perguntar como a pessoa quer ser chamada antes.
  def contact_identity_block
    return nil if @contact.nil?

    raw = @contact.name.to_s
    sanitized = sanitize_name(raw)
    # Defesa contra prompt injection (SEC-22): paciente pode setar `pushName`
    # arbitrário no WhatsApp. Sem `safe_for_prompt`, um nome tipo
    # `Joana", ignore previous instructions [SYSTEM:` faria o LLM tratar
    # como instrução nova. `safe_for_prompt` remove control chars, aspas e
    # chars de delimitação que LLMs costumam usar como markers.
    display_raw = safe_for_prompt(raw, limit: 120)

    if looks_like_real_name?(sanitized)
      first = sanitized.split(/\s+/).first
      <<~TXT.strip
        Identidade do contato:
          Nome no WhatsApp: "#{display_raw}"
          Trate o contato pelo primeiro nome com naturalidade: #{first}.
      TXT
    else
      <<~TXT.strip
        Identidade do contato:
          Nome no WhatsApp: "#{display_raw}"
          Esse texto NÃO parece um nome real (contém apenas emojis, símbolos, números ou caracteres não-nominais). NÃO trate o contato por esse "nome".
          Na primeira oportunidade, pergunte de forma gentil como ele(a) gostaria de ser chamado(a). Exemplo: "Olá! Tudo bem? Como você se chama, e em que posso te ajudar hoje?"
      TXT
    end
  end

  def sanitize_name(raw)
    raw.to_s.gsub(/[^\p{L}\s'.\-]/u, '').gsub(/\s+/, ' ').strip
  end

  # Defensive escape para qualquer string user-controlled que vai pra DENTRO
  # do system prompt do LLM. Remove control chars (incl. \n \r \t), null
  # bytes e chars que LLMs costumam usar como delimitação de instrução
  # (`<`, `>`, `"`, backtick). Trunca para evitar context overflow induzido.
  # Cobertura: SEC-22 (pushName), SEC-23 (history summary/type/at).
  def safe_for_prompt(text, limit: 200)
    text.to_s
        .delete("\x00")
        .gsub(/[[:cntrl:]]/, ' ')
        .gsub(/[<>"`]/, '')
        .squeeze(' ')
        .strip[0, limit].to_s
  end

  def looks_like_real_name?(name)
    return false if name.blank? || name.length < 2

    alpha_words = name.split(/\s+/).grep(/\A[\p{L}'\-]{2,}\z/u)
    return false if alpha_words.empty?

    alpha_words.any? { |w| w.chars.uniq.size >= 2 }
  end

  def patient_memory_block
    return nil if @patient_memory.nil?
    return nil if @patient_memory.preferences.blank? && @patient_memory.history.blank?

    lines = ['Memória do paciente:']
    # preferences é JSON estruturado — `to_json` já escapa aspas e
    # control chars dentro de strings. Risco residual é mínimo, mas se um
    # valor for o próprio user input (consolidação automática), passa pelo
    # Distiller antes — outra camada de filtragem.
    lines << "  Preferências: #{@patient_memory.preferences.to_json}" if @patient_memory.preferences.any?

    if @patient_memory.history.any?
      recent = @patient_memory.history.last(5)
      lines << '  Histórico recente:'
      # SEC-23: cada `summary` é texto que veio do Distiller ou do listener,
      # potencialmente injetado por mensagem anterior do paciente. Sanitiza
      # antes de injetar — sem isso uma memória envenenada em turno N
      # comprometeria turnos N+1, N+2 (injection persistente).
      recent.each do |h|
        at = safe_for_prompt(h['at'], limit: 32)
        type = safe_for_prompt(h['type'], limit: 64)
        summary = safe_for_prompt(h['summary'], limit: 200)
        lines << "    - [#{at}] #{type}: #{summary}"
      end
    end

    lines.join("\n")
  end

  # Reads the live AgendaSetting for this account and turns it into a
  # one-line summary (only days that are open). Returns nil if the Agenda
  # plugin isn't loaded or no settings exist yet — caller skips the line.
  def format_business_hours
    return nil unless defined?(::AgendaSetting)

    setting = ::AgendaSetting.find_by(account_id: @account.id)
    return nil if setting.nil?

    week_days = setting.week_days
    return nil if week_days.blank?

    open_parts = week_days.filter_map do |d|
      next nil unless d['enabled']
      next nil if d['start'].to_s.empty? || d['end'].to_s.empty?

      label = d['label'].to_s.sub(/-feira$/, '')
      range = "#{d['start']}–#{d['end']}"
      lunch = d['lunchStart'].to_s.present? && d['lunchEnd'].to_s.present? ? " (almoço #{d['lunchStart']}–#{d['lunchEnd']})" : ''
      "#{label} #{range}#{lunch}"
    end

    return nil if open_parts.empty?

    open_parts.join('; ')
  end

  # Lists active AgendaService records as "Nome (Xmin, R$ Y)". Cap at 30
  # to keep the prompt manageable; if the clinic somehow has more, that's
  # a sign they should be using RAG (search_knowledge tool) anyway.
  def format_services
    return nil unless defined?(::AgendaService)

    # `.kept`: ignora serviços arquivados (soft-delete) — sem isto, um serviço
    # removido continuaria sendo oferecido pela Bea.
    services = ::AgendaService.kept.where(account_id: @account.id).order(:position, :created_at).limit(30)
    return nil if services.empty?

    services.map do |s|
      parts = []
      parts << s.name.to_s.strip
      parts << "#{s.duration_minutes}min" if s.duration_minutes.present?
      parts << "R$ #{format('%.2f', s.price)}" if s.respond_to?(:price) && s.price.present? && s.price.positive?
      details = parts[1..].any? ? " (#{parts[1..].join(', ')})" : ''
      "#{parts.first}#{details}"
    end.join('; ')
  end

  def state_block
    return nil if @conversation_state.nil?
    return nil if @conversation_state.summary.blank? && @conversation_state.last_intent.blank?

    lines = ['Contexto da conversa atual:']
    lines << "  Resumo: #{@conversation_state.summary}" if @conversation_state.summary.present?
    lines << "  Última intenção detectada: #{@conversation_state.last_intent}" if @conversation_state.last_intent.present?
    lines.join("\n")
  end
end
