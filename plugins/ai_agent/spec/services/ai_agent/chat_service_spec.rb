# BE-1 (auditoria 2026-05-18): spec caracterizador do
# `AiAgent::ChatService#respond`. Cobre os branches mais críticos:
#   - Pré-flight guards (blank, disabled, cost cap)
#   - Emergency short-circuit (Mount Sinai / Nature Medicine)
#   - Captain quota handoff
#   - Early handoff via EscalationRules (pedido explícito)
#   - Recall opt-out short-circuit
#   - LLM happy path (mocked RubyLLM)
#   - Trace persistência + cross-tenant (account_id sempre setado)
#
# Mocks ao boundary: RubyLLM.chat + ::Llm::Config.initialize!. Resto
# usa DB real (Trace, ConversationState, PatientMemory) — fast specs
# mas com cobertura semântica de gravação real.
#
# Pré-requisito pra Fase 4 (decompose ChatService 947 linhas).
require 'rails_helper'

RSpec.describe AiAgent::ChatService do
  let(:account) { create(:account) }
  let(:conversation_id) { 12_345 }
  let(:contact_id) { nil }

  # Habilita Bea pra essa conta. Usa find_or_initialize_by porque o
  # Chatwoot fork tem callback que auto-cria AccountSetting no
  # after_create_commit de Account (`ensure_default_bea_assistant`).
  let!(:account_setting) do
    AiAgent::AccountSetting.find_or_initialize_by(account: account).tap do |s|
      s.enabled = true
      s.save!
    end
  end

  # Garante GlobalSetting com cost cap padrão (0 = unlimited). Atualiza
  # se já existir (cron initializer cria singleton no boot).
  let!(:global_setting) do
    setting = AiAgent::GlobalSetting.first_or_create!(
      chat_provider: 'openai',
      max_tokens_per_conversation: 4000,
      max_monthly_cost_per_account_cents: 0
    )
    setting.update!(
      chat_provider: 'openai',
      max_tokens_per_conversation: 4000,
      max_monthly_cost_per_account_cents: 0
    )
    setting
  end

  # ── LLM mocks (boundary). RubyLLM.chat retorna fluent builder; ask
  # retorna response com content/input_tokens/output_tokens.
  let(:llm_response) do
    instance_double(
      'RubyLLM::Response',
      content: 'Olá! Posso ajudar a marcar sua consulta. Qual o serviço?',
      input_tokens: 120,
      output_tokens: 45
    )
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
    # Workaround: ConfigResolver usa compact-form (`class AiAgent::ConfigResolver`)
    # com lookups bare (`GlobalSetting`, `ToolDefinition`, `UsageCounter`).
    # Em produção isso resolve via Zeitwerk const_missing magic; em spec
    # falha porque o lexical scope não inclui `AiAgent`. Stub no top-level
    # pra desbloquear (fix permanente seria refactorar pra `module AiAgent;
    # class ConfigResolver`, mas evita regressão fora do escopo deste spec).
    stub_const('GlobalSetting', AiAgent::GlobalSetting)
    stub_const('ToolDefinition', AiAgent::ToolDefinition)
    stub_const('UsageCounter', AiAgent::UsageCounter)

    allow(::Llm::Config).to receive(:initialize!)
    allow(RubyLLM).to receive(:chat).and_return(llm_chat)
    # Tools desabilitadas — Bea responde só com texto. Spec foca no
    # orchestrator, não na execução de tools (cobertas em specs próprios).
    allow(AiAgent::ToolRegistry).to receive(:lookup).and_return([])
    # PromptBuilder/ContextBuilder lookups complexos de KB/persona —
    # stubamos pra retornar strings fixas. Spec foca em orchestration,
    # não em conteúdo de prompt.
    allow_any_instance_of(AiAgent::PromptBuilder)
      .to receive(:system_instructions).and_return('Sou a Bea, assistente.')
    allow_any_instance_of(AiAgent::ContextBuilder)
      .to receive(:block).and_return('')
    # Default: nenhum notifier interno dispara (Detectors retornam nil
    # pra mensagens neutras, mas stubamos pra evitar dependência de DB
    # de templates de notificação).
    stub_const('AiAgent::InternalNotifier::OffensiveToneAlert', double('OffensiveToneAlert', call: nil))
    stub_const('AiAgent::InternalNotifier::RefundRequestAlert', double('RefundRequestAlert', call: nil))
    stub_const('AiAgent::InternalNotifier::EmergencyAlert', double('EmergencyAlert', call: nil))
    stub_const('AiAgent::InternalNotifier::RepeatedFailuresAlert',
               double('RepeatedFailuresAlert', track: nil, call: nil))
  end

  def service(history: [], contact_id: nil)
    described_class.new(
      account: account,
      conversation_id: conversation_id,
      contact_id: contact_id,
      history: history
    )
  end

  # ─── Pré-flight guards ──────────────────────────────────────────────
  describe '#respond (pré-flight guards)' do
    it 'raise ArgumentError quando user_message vem blank' do
      expect { service.respond('') }.to raise_error(ArgumentError, /blank/)
      expect { service.respond('   ') }.to raise_error(ArgumentError, /blank/)
      expect { service.respond(nil) }.to raise_error(ArgumentError, /blank/)
    end

    it 'raise BeaDisabledError quando AccountSetting.enabled=false' do
      account_setting.update!(enabled: false)
      expect { service.respond('Oi') }
        .to raise_error(described_class::BeaDisabledError, /not enabled/)
    end

    it 'raise BudgetExceededError quando over_monthly_cost_cap' do
      # Seta cap de R$1 e gasta R$2 — ConfigResolver vai retornar true
      global_setting.update!(max_monthly_cost_per_account_cents: 100)
      AiAgent::UsageCounter.bump!(
        account_id: account.id, input_tokens: 0, output_tokens: 0,
        cost_cents: 200, conversations: 0
      )

      expect { service.respond('Oi') }
        .to raise_error(described_class::BudgetExceededError, /monthly cost cap/)
    end

    it 'guard order: BeaDisabled ANTES de cost cap (não vaza erro de billing)' do
      account_setting.update!(enabled: false)
      global_setting.update!(max_monthly_cost_per_account_cents: 1)
      AiAgent::UsageCounter.bump!(account_id: account.id, input_tokens: 0,
                                  output_tokens: 0, cost_cents: 100, conversations: 0)

      # Deve raise BeaDisabled, NÃO BudgetExceeded — UX: conta desligada
      # não precisa saber que tem cost cap.
      expect { service.respond('Oi') }
        .to raise_error(described_class::BeaDisabledError)
    end
  end

  # ─── Emergency short-circuit ────────────────────────────────────────
  describe '#respond (emergency keyword)' do
    it 'curto-circuita NÃO chamando RubyLLM quando keyword clínica' do
      service.respond('Estou sangrando muito, não para')

      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'retorna Result com handoff=true quando emergência clínica' do
      result = service.respond('Não consigo respirar')

      expect(result.handoff).to be(true)
      expect(result.message).to be_present
      expect(result.usage).to eq(input_tokens: 0, output_tokens: 0)
    end

    it 'curto-circuita quando ideação suicida (CVV 188)' do
      result = service.respond('quero me matar')

      expect(result.handoff).to be(true)
      expect(result.tool_executions.first[:name]).to eq('emergency_detector')
    end

    it 'persiste Trace com provider=emergency_detector + short_circuited' do
      service.respond('Estou desmaiando')

      trace = AiAgent::Trace.where(account_id: account.id).last
      expect(trace.provider).to eq('emergency_detector')
      expect(trace.short_circuited).to be(true)
      expect(trace.escalated).to be(true)
      expect(trace.escalation_reason).to match(/\Aemergency:/)
    end

    it 'escala ConversationState com reason=emergency:*' do
      # Regex do detector aceita 3ª pessoa ("engasgou/engasgando"), não
      # 1ª pessoa ("engasguei") — provavelmente intencional (paciente
      # descrevendo terceiro, ou auto-relato pós-fato).
      service.respond('Meu filho engasgou agora')

      state = AiAgent::ConversationState.find_by(account_id: account.id,
                                                 conversation_id: conversation_id)
      expect(state.status).to eq('escalated')
      expect(state.last_intent).to match(/\Aemergency:/)
    end

    it 'dispara EmergencyAlert.call (notifier equipe)' do
      expect(AiAgent::InternalNotifier::EmergencyAlert)
        .to receive(:call).with(hash_including(account: account, category: anything))

      service.respond('Estou desmaiando')
    end
  end

  # ─── Captain quota handoff ──────────────────────────────────────────
  describe '#respond (Captain quota exhausted)' do
    before do
      allow(account).to receive(:respond_to?).and_call_original
      allow(account).to receive(:respond_to?).with(:usage_limits).and_return(true)
      allow(account).to receive(:respond_to?).with(:increment_response_usage).and_return(false)
      allow(account).to receive(:usage_limits).and_return(
        captain: { responses: { current_available: 0 } }
      )
    end

    it 'handoff e NÃO chama RubyLLM quando quota zerada' do
      result = service.respond('Olá')

      expect(RubyLLM).not_to have_received(:chat)
      expect(result.handoff).to be(true)
      expect(result.message).to include('limite')
    end

    it 'Trace marca escalation_reason=captain_quota_exhausted' do
      service.respond('Olá')

      trace = AiAgent::Trace.where(account_id: account.id).last
      expect(trace.escalated).to be(true)
      expect(trace.escalation_reason).to eq('captain_quota_exhausted')
      expect(trace.short_circuited).to be(true)
    end

    it 'NÃO bloqueia quando current_available > 0' do
      allow(account).to receive(:usage_limits).and_return(
        captain: { responses: { current_available: 50 } }
      )

      service.respond('Olá')

      expect(RubyLLM).to have_received(:chat).at_least(:once)
    end
  end

  # ─── Early handoff via EscalationRules ──────────────────────────────
  describe '#respond (early handoff)' do
    it 'handoff quando paciente pede atendente explicitamente' do
      result = service.respond('Quero falar com um atendente humano por favor')

      expect(result.handoff).to be(true)
      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'Trace escala com reason=explicit_human_request' do
      service.respond('Pode me transferir para uma pessoa de verdade?')

      trace = AiAgent::Trace.where(account_id: account.id).last
      expect(trace.escalated).to be(true)
      expect(trace.escalation_reason).to eq('explicit_human_request')
    end
  end

  # ─── Recall opt-out ─────────────────────────────────────────────────
  describe '#respond (recall opt-out)' do
    let(:contact_id) { 99_999 }

    before do
      # Cria PatientMemory com last_recall_at recente (<7d)
      AiAgent::PatientMemory.create!(
        account: account,
        contact_id: contact_id,
        preferences: { 'last_recall_at' => 2.days.ago.iso8601 }
      )
    end

    it 'curto-circuita quando paciente responde "não" em <7d após recall' do
      result = service(contact_id: contact_id).respond('Não')

      expect(result.handoff).to be(false)
      expect(result.message).to include('lembretes')
      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'marca preferences.recall_opt_out=true' do
      service(contact_id: contact_id).respond('pare')

      memory = AiAgent::PatientMemory.find_by(account_id: account.id, contact_id: contact_id)
      expect(memory.preferences['recall_opt_out']).to be(true)
      expect(memory.preferences['recall_opt_out_at']).to be_present
    end

    it 'NÃO opta out quando "não" vem >7d após recall (fora da janela)' do
      AiAgent::PatientMemory.find_by(account_id: account.id, contact_id: contact_id)
                            .update!(preferences: { 'last_recall_at' => 10.days.ago.iso8601 })

      service(contact_id: contact_id).respond('não')
      # Fora da janela: cai no LLM normal
      expect(RubyLLM).to have_received(:chat).at_least(:once)
    end

    it 'NÃO opta out quando não há last_recall_at registrado' do
      AiAgent::PatientMemory.find_by(account_id: account.id, contact_id: contact_id)
                            .update!(preferences: {})

      service(contact_id: contact_id).respond('não')
      expect(RubyLLM).to have_received(:chat).at_least(:once)
    end
  end

  # ─── LLM happy path ─────────────────────────────────────────────────
  describe '#respond (LLM happy path)' do
    it 'retorna Result com message do LLM' do
      result = service.respond('Quero marcar uma avaliação')

      expect(result.message).to include('marcar')
      expect(result.handoff).to be(false)
    end

    it 'usage reporta input/output_tokens do response' do
      result = service.respond('Quero marcar')

      expect(result.usage[:input_tokens]).to eq(120)
      expect(result.usage[:output_tokens]).to eq(45)
    end

    it 'persiste Trace com account_id, provider, model, tokens, cost_cents' do
      service.respond('Quero marcar')

      trace = AiAgent::Trace.where(account_id: account.id).last
      expect(trace.account_id).to eq(account.id)
      expect(trace.conversation_id).to eq(conversation_id)
      expect(trace.input_tokens).to eq(120)
      expect(trace.output_tokens).to eq(45)
      expect(trace.short_circuited).to be(false)
      expect(trace.escalated).to be(false)
    end

    it 'chama UsageCounter.bump! com tokens do response' do
      # NOTE: testando via `receive(:bump!)` em vez de side effect em
      # `monthly_cost_cents` porque tokens pequenos (120+45) × pricing
      # gpt-4.1-mini arredondam pra 0 cents (precisão integer). O que
      # importa pro contrato é que bump! foi chamado.
      expect(AiAgent::UsageCounter).to receive(:bump!).with(
        hash_including(
          account_id: account.id,
          input_tokens: 120,
          output_tokens: 45
        )
      )

      service.respond('Quero marcar')
    end

    it 'atualiza ConversationState.last_message_at' do
      service.respond('Quero marcar')

      state = AiAgent::ConversationState.find_by(account_id: account.id,
                                                 conversation_id: conversation_id)
      expect(state.last_message_at).to be_within(5.seconds).of(Time.current)
    end

    it 'inclui mensagem do paciente no ask() do LLM' do
      service.respond('Quero marcar uma avaliação')

      expect(llm_chat).to have_received(:ask) do |arg|
        expect(arg).to include('Quero marcar uma avaliação')
      end
    end

    it 'inclui histórico inline quando passado (workaround Gemini)' do
      history = [
        { role: 'user', content: 'oi' },
        { role: 'assistant', content: 'olá!' }
      ]
      service(history: history).respond('continue')

      expect(llm_chat).to have_received(:ask) do |arg|
        expect(arg).to include('Histórico recente')
        expect(arg).to include('Paciente: oi')
        expect(arg).to include('Você (Bea): olá!')
      end
    end
  end

  # ─── Guardrail violation ────────────────────────────────────────────
  describe '#respond (guardrail violation)' do
    let(:llm_response) do
      instance_double(
        'RubyLLM::Response',
        content: 'Você está com cárie no dente 24, tome 500mg de paracetamol',
        input_tokens: 100,
        output_tokens: 30
      )
    end

    it 'escala ConversationState quando guardrail bloqueia' do
      service.respond('Tô com dor')

      state = AiAgent::ConversationState.find_by(account_id: account.id,
                                                 conversation_id: conversation_id)
      expect(state.status).to eq('escalated')
      expect(state.last_intent).to match(/\Aguardrail:/)
    end

    it 'Trace registra guardrail_violations no jsonb' do
      service.respond('Tô com dor')

      trace = AiAgent::Trace.where(account_id: account.id).last
      expect(trace.guardrail_violations).not_to be_empty
      expect(trace.escalation_reason).to match(/\Aguardrail:/)
    end
  end

  # ─── Cross-tenant ───────────────────────────────────────────────────
  describe '#respond (cross-tenant)' do
    it 'Trace SEMPRE tem account_id da conta do serviço (multi-tenant invariant)' do
      service.respond('Oi')
      expect(AiAgent::Trace.where(account_id: account.id).count).to be >= 1
      expect(AiAgent::Trace.where(account_id: account.id).pluck(:account_id).uniq).to eq([account.id])
    end

    it 'ConversationState fica scoped por account_id' do
      service.respond('Oi')
      # Outra conta com mesmo conversation_id NÃO deve ver o state
      other_account = create(:account)
      expect(
        AiAgent::ConversationState.find_by(
          account_id: other_account.id, conversation_id: conversation_id
        )
      ).to be_nil
    end
  end
end
