# Auditoria BIA.md — CAMADA DE FLUXO / ROTEAMENTO (FASE 1b).
#
# O "qual tool chamar" é decisão do LLM (coberto pela suite ao-vivo
# /tmp/bia_suite.rb). Aqui testamos os trilhos DETERMINÍSTICOS que rodam
# ANTES/DEPOIS do LLM e garantem o comportamento que o dono exigiu:
#   - anti-escalação espúria (NÃO jogar pra humano quando o paciente só
#     recusou/encerrou) e handoff legítimo só em pedido explícito (T04/T09)
#   - frase banida "atendente humano" → "setor responsável" na saída
#   - o "cérebro" da autonomia: oferta → confirmação curta → book sem LLM,
#     e memória anti-duplicação depois de agendar (T16/T08, transversais)
require 'rails_helper'

RSpec.describe 'BIA.md — fluxo/roteamento determinístico' do
  # ── T04/T09 + transversal — quando escalar pra humano ───────────────
  describe 'EscalationRules — handoff só quando deve' do
    def decision_for(message)
      state = instance_double(AiAgent::ConversationState,
                              consecutive_negative_count: 0,
                              consecutive_tool_failures: 0,
                              working_memory: {})
      AiAgent::Humanization::EscalationRules.new(state, last_user_message: message).evaluate
    end

    # A queixa nº1 do dono: a Bia jogava pra equipe quando o paciente só
    # disse "não". Recusar/encerrar NÃO pode escalar.
    it 'NAO_escala_quando_paciente_recusa_ou_encerra' do
      ['Não, obrigado!', 'Não, era só isso. Obrigada!', 'Agora não, valeu',
       'Pode ser depois', 'Deixa pra lá'].each do |msg|
        expect(decision_for(msg).escalate?).to be(false), "escalou indevidamente em: #{msg.inspect}"
      end
    end

    it 'T04_escala_quando_paciente_pede_humano_explicitamente' do
      decision = decision_for('Quero falar com um atendente, por favor')

      expect(decision.escalate?).to be(true)
      expect(decision.reason).to eq('explicit_human_request')
    end

    it 'T09_pedido_de_recepcao_conta_como_handoff_explicito' do
      expect(decision_for('Preciso falar com a recepção').escalate?).to be(true)
    end

    it 'escala_em_sinal_clinico_urgente' do
      expect(decision_for('Estou com dor muito forte').escalate?).to be(true)
    end
  end

  # ── Transversal — frase banida pelo dono na SAÍDA ───────────────────
  describe 'Guardrail — "atendente humano" vira "setor responsável"' do
    def sanitize(text)
      AiAgent::Guardrail::Validator.new(text).call
    end

    it 'troca_atendente_humano_por_setor_responsavel' do
      result = sanitize('Tudo bem! Vou te transferir para um atendente humano agora.')

      expect(result).to be_safe
      expect(result.sanitized_message).to include('setor responsável')
      expect(result.sanitized_message).not_to match(/atendente humano/i)
    end

    it 'troca_atendimento_humano_tambem' do
      result = sanitize('Vou encaminhar pro atendimento humano.')

      expect(result.sanitized_message).to include('setor responsável')
      expect(result.sanitized_message).not_to match(/atendimento humano/i)
    end

    it 'nao_mexe_em_texto_normal' do
      result = sanitize('Perfeito! Seu agendamento está confirmado. 😊')

      expect(result.sanitized_message).to eq('Perfeito! Seu agendamento está confirmado. 😊')
    end

    # O dono não quer travessão "—" nem meia-risca "–" em mensagem nenhuma.
    it 'remove_travessao_e_meia_risca_da_saida' do
      r1 = sanitize('Como posso te ajudar — o contato é sobre a consulta?')
      r2 = sanitize('Tem horário às 14h – confirma?')

      expect(r1.sanitized_message).not_to include('—')
      expect(r1.sanitized_message).to eq('Como posso te ajudar, o contato é sobre a consulta?')
      expect(r2.sanitized_message).not_to include('–')
      expect(r2.sanitized_message).to eq('Tem horário às 14h, confirma?')
    end

    it 'ao_trocar_travessao_nao_deixa_virgula_colada_na_pontuacao' do
      result = sanitize('Boa noite! — Vi que você tem cadastro.')

      expect(result.sanitized_message).to eq('Boa noite! Vi que você tem cadastro.')
    end
  end

  # ── Transversal — anti-vazamento de raciocínio (chain-of-thought) ───
  describe 'ReasoningLeak — bloqueia o raciocínio do LLM de vazar pro paciente' do
    def leaked?(text) = AiAgent::Guardrail::ReasoningLeak.leaked?(text)

    it 'flagra o vazamento REAL do teste ao vivo' do
      leak = 'Como o Leandro escolheu o horário das 10:00 e não possui cadastro ' \
             '(retornou found: false), preciso solicitar o Nome Completo e o CPF dele. Uma pergunta por vez.'
      expect(leaked?(leak)).to be(true)
    end

    it 'flagra nome de tool e citação de regra' do
      expect(leaked?('Vou usar o create_patient_minimal pra te cadastrar')).to be(true)
      expect(leaked?('Pra manter o limite de 3 frases, vou primeiro confirmar')).to be(true)
    end

    it 'NÃO flagra fala natural ao paciente' do
      expect(leaked?('Esse agendamento é para você mesmo? E me passa seu nome completo e o CPF, por favor.')).to be(false)
    end

    it 'NÃO flagra "confirmar com a equipe" (encaminhamento legítimo)' do
      expect(leaked?('Deixa eu confirmar isso com a equipe e já te retorno!')).to be(false)
    end

    it 'strip remove a frase vazada e mantém a pergunta ao paciente' do
      mixed = 'Preciso solicitar o CPF dele. Esse agendamento é para você mesmo?'
      cleaned = AiAgent::Guardrail::ReasoningLeak.strip(mixed)
      expect(cleaned).to include('para você mesmo')
      expect(cleaned).not_to match(/CPF dele/)
    end
  end

  # ── Transversal — emergência: urgência dentária ≠ SAMU ──────────────
  describe 'Emergency::Detector — não manda urgência dentária pro SAMU' do
    def detect(msg) = AiAgent::Emergency::Detector.new(msg).call

    it 'NÃO dispara pra dente quebrado + sangue + bruxismo (queixa do dono)' do
      expect(detect('Tenho bruxismo e meus dentes estão quebrando e com MUITO sangue')).to be_nil
    end

    it 'NÃO dispara pra sangramento na gengiva' do
      expect(detect('minha gengiva está sangrando muito')).to be_nil
    end

    it 'AINDA dispara pra hemorragia SEM contexto odontológico' do
      expect(detect('cortei o braço e estou perdendo muito sangue')&.category).to eq(:clinical)
    end

    it 'AINDA dispara pra risco de vida real (não respira)' do
      expect(detect('não consigo respirar')&.category).to eq(:clinical)
    end

    it 'AINDA dispara pra ideação suicida' do
      expect(detect('quero me matar')&.category).to eq(:suicidal)
    end
  end

  # ── T16/T08 — o "cérebro" da autonomia (ConversationContext) ────────
  describe 'ConversationContext — oferta → confirmação → memória' do
    let(:account) { create(:account) }
    let(:state)   { AiAgent::ConversationState.for(account: account, conversation_id: 4242) }
    let(:ctx)     { AiAgent::StateMachine::ConversationContext.new(state) }

    it 'reconhece_confirmacao_curta_e_ignora_recusa' do
      expect(ctx.confirmation?('sim')).to be(true)
      expect(ctx.confirmation?('pode')).to be(true)
      expect(ctx.confirmation?('Não, obrigado')).to be(false)
      expect(ctx.confirmation?('sim, mas só semana que vem')).to be(false) # tem conteúdo extra → vai pro LLM
    end

    it 'T08_casa_horario_especifico_mencionado_com_a_oferta' do
      ctx.offer_slot!(
        starts_at: '2026-07-10T09:00:00-03:00', duration_minutes: 60,
        service_id: 7, service_name: 'Avaliação', user_id: 5, professional_name: 'Dra. Ana',
        alternatives: [
          { 'starts_at' => '2026-07-10T09:00:00-03:00', 'user_id' => 5, 'professional_name' => 'Dra. Ana' },
          { 'starts_at' => '2026-07-10T11:00:00-03:00', 'user_id' => 5, 'professional_name' => 'Dra. Ana' }
        ]
      )

      matched = ctx.offer_match_for('pode ser as 11h?')

      expect(matched).to be_present
      expect(matched['starts_at']).to eq('2026-07-10T11:00:00-03:00')
    end

    it 'T16_memoria_anti_duplicacao_lembra_que_ja_agendou' do
      ctx.mark_completed!(type: 'booked', summary: 'Avaliação em 10/07 às 09:00 ✅')

      done = ctx.recent_completed
      expect(done['type']).to eq('booked')
      expect(ctx.pending_offer).to be_nil # marcar concluído limpa a oferta pendente
    end
  end

  # ── Transversal (integração real) — sanitização chega ao paciente ───
  # Prova que o sanitizer está ligado no orquestrador: o que o LLM gerar
  # com "atendente humano" sai limpo pro paciente. Mocka só o boundary do
  # LLM (mesmo padrão do chat_service_spec).
  describe 'ChatService aplica o sanitizer na resposta final' do
    let(:account) { create(:account) }
    let(:conversation_id) { 7777 }

    let!(:account_setting) do
      AiAgent::AccountSetting.find_or_initialize_by(account: account).tap do |s|
        s.enabled = true
        s.save!
      end
    end
    let!(:global_setting) do
      AiAgent::GlobalSetting.first_or_create!(chat_provider: 'openai', max_tokens_per_conversation: 4000,
                                              max_monthly_cost_per_account_cents: 0)
    end
    # String form (não a constante) de propósito: RubyLLM::Response não fica
    # carregada no boot de teste — mesmo padrão do chat_service_spec.
    let(:llm_response) do
      instance_double('RubyLLM::Response',
                      content: 'Claro! Vou te transferir para um atendente humano agora.',
                      input_tokens: 50, output_tokens: 20)
    end
    let(:llm_chat) do
      chat = double('RubyLLM::Chat')
      allow(chat).to receive(:with_instructions).and_return(chat)
      allow(chat).to receive(:with_tool).and_return(chat)
      allow(chat).to receive(:on_tool_call).and_return(chat)
      allow(chat).to receive(:ask).and_return(llm_response)
      chat
    end

    before do
      stub_const('GlobalSetting', AiAgent::GlobalSetting)
      stub_const('ToolDefinition', AiAgent::ToolDefinition)
      stub_const('UsageCounter', AiAgent::UsageCounter)
      allow(Llm::Config).to receive(:initialize!)
      allow(RubyLLM).to receive(:chat).and_return(llm_chat)
      allow(AiAgent::ToolRegistry).to receive(:lookup).and_return([])
      allow_any_instance_of(AiAgent::PromptBuilder).to receive(:system_instructions).and_return('Sou a Bea.')
      allow_any_instance_of(AiAgent::ContextBuilder).to receive(:block).and_return('')
    end

    it 'resposta_final_nao_contem_a_frase_banida' do
      result = AiAgent::ChatService.new(
        account: account, conversation_id: conversation_id, contact_id: nil, history: []
      ).respond('Não consegui resolver aqui')

      expect(result.message).to include('setor responsável')
      expect(result.message).not_to match(/atendente humano/i)
    end
  end

  # Pedido do dono: nos testes, a Bea SÓ responde o número dele.
  describe 'Gate de allowlist de telefone (CAPTAIN_BEA_PHONE_ALLOWLIST)' do
    def allowed?(phone)
      conv = Struct.new(:contact, :contact_inbox).new(Struct.new(:phone_number).new(phone), nil)
      AiAgent::ChatResponseJob.new.send(:phone_allowed?, conv)
    end

    it 'sem allowlist responde todos (produção)' do
      InstallationConfig.where(name: 'CAPTAIN_BEA_PHONE_ALLOWLIST').delete_all
      expect(allowed?('+5511999998888')).to be(true)
    end

    it 'com allowlist só responde os números listados' do
      InstallationConfig.create!(name: 'CAPTAIN_BEA_PHONE_ALLOWLIST', value: '+5511975577204')
      expect(allowed?('+5511975577204')).to be(true)
      expect(allowed?('+5511999998888')).to be(false)
    end
  end

  # Regressão 2026-06-11: "Sim" determinístico bookou 09:00 (oferta velha)
  # criando uma 3ª consulta, em vez de remarcar a discutida pra 15:00.
  describe 'Auto-book do "Sim" — casos em que ele NÃO pode agir sozinho' do
    let(:account) { create(:account) }

    def service_for
      AiAgent::ChatService.new(account: account, conversation_id: 1, contact_id: nil, history: [])
    end

    it 'oferta ambígua (2+ consultas listadas) vai pro LLM, não auto-booka' do
      expect(service_for.send(:book_from_offer, { 'ambiguous_reschedule' => true }, nil)).to be_nil
    end

    it 'remarcação dirigida (target_appointment_id) vai pro LLM (motivo é obrigatório)' do
      expect(service_for.send(:book_from_offer, { 'target_appointment_id' => 42 }, nil)).to be_nil
    end
  end
end
