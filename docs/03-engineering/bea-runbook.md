# Runbook Operacional — Bea (AI Agent)

> Documento de referência para suporte e ops da Bea em produção.
> Última atualização: 2026-05-05.

## 📋 TL;DR

A Bea é o agente de IA da Klivy, plugado como AgentBot do Chatwoot. Responde mensagens incoming em qualquer inbox de uma conta com Bea ativa, consultando RAG e tools internas (agenda, financeiro, prontuário). Provider primário: Gemini. Fallback automático: OpenAI.

---

## 1. Configuração Inicial

### 1.1 Habilitar Provider (Super Admin)

1. Acessar `/super_admin/bea`.
2. Em **Provider Ativo**, selecionar `Gemini`.
3. Colar a chave em **Gemini API Key** ([gere em ai studio](https://aistudio.google.com/apikey)).
4. (Opcional) Em **Modelo Padrão**, escrever `gemini-2.0-flash`. Em branco usa default.
5. (Opcional) Configurar OpenAI também — ela vira fallback automático em outage do Gemini.
6. Salvar.

### 1.2 Habilitar Bea numa Conta

1. Super Admin → Contas → [conta] → **Configurar Bea**.
2. Marcar **Bea ativa nesta conta**.
3. (Opcional) Selecionar persona (`Bea — Odontologia` / `Estética` / `Bem-estar`).
4. (Opcional) Definir budget mensal de tokens.
5. Salvar.

### 1.3 Subir Documentos pra RAG

1. Super Admin → Contas → [conta] → Configurar Bea → **Documentos**.
2. Enviar PDF (até 20 MB).
3. Aguardar status mudar `pending → processing → processed`. Falhas mostram erro inline.

---

## 2. Como Bea Decide Responder

```
mensagem incoming chega
  ↓
MessageListener filtra:
  • só incoming
  • Bea ativa na conta
  • conversa não escalada
  • sem assignee humano
  • dentro do rate limit (60/h por conv, 2000/dia por conta)
  ↓
ChatResponseJob (typing_on)
  ↓
ChatService:
  1. track repetition
  2. apply sentiment (LLM leve)
  3. EscalationRules → pode escalar SEM chamar LLM principal
  4. RubyLLM.chat (Gemini → fallback OpenAI se erro)
     • search_knowledge (RAG)
     • patient_lookup / list_appointments / financial_status
     • notify_staff / transfer_to_human
  5. Guardrail::Validator (bloqueia diagnóstico/prescrição/garantia)
  6. persist Trace + bump UsageCounter
  ↓
Message outgoing posted (typing_off no ensure)
```

---

## 3. Troubleshooting

### Bea não está respondendo

Checar em ordem:

1. **Bea ativa na conta?** Super Admin → Contas → Configurar Bea → Status.
2. **Provider configurado?** `/super_admin/bea` → API key não-vazia.
3. **Conversa tem assignee humano?** Listener pula nesse caso. Desatribua se quer Bea de volta.
4. **Conversa escalada?**
   ```ruby
   AiAgent::ConversationState.find_by(conversation_id: <id>)&.status
   # Se for "escalated", a Bea não responde mais. Reset:
   .update!(status: 'active')
   ```
5. **Rate limited?** Logs do Rails procurando `[AiAgent] rate limited:`.
6. **Sidekiq processando?** `/monitoring/sidekiq` deve ter `ChatResponseJob` na fila ou processado.

### Bea escalando demais

Verificar `AiAgent::Trace` últimos 50 turnos:

```ruby
AiAgent::Trace.order(created_at: :desc).limit(50).pluck(:escalation_reason).tally
```

Razões possíveis:

- `explicit_human_request` — paciente pediu (ok, comportamento correto)
- `urgent_clinical_signal` — disparo por keyword de urgência (revisar regex se for falso positivo)
- `consecutive_negative_sentiment` — conversa frustrante; revisar persona/RAG
- `consecutive_tool_failures` — alguma tool com bug; ver `AiAgent::Trace.where("error_message IS NOT NULL")`
- `user_loop` — usuário mandando mesma mensagem (3×); pode ser bot, ok escalar
- `guardrail:medical_diagnosis|prescription|guarantee` — Bea estava prestes a falar coisa proibida; ajustar persona

### Custo subindo

```ruby
AiAgent::Trace.where(created_at: 7.days.ago..)
              .group(:model)
              .sum('cost_cents')
# {"gemini-2.0-flash" => 1234, ...}
```

Se Gemini estiver 0 e OpenAI alto: outage do Gemini ativando fallback. Verificar `RubyLLM.config.gemini_api_key` válida.

### Resposta da Bea vazia ou estranha

```ruby
# Olhar último Trace da conversa
AiAgent::Trace.where(conversation_id: <id>).order(created_at: :desc).first
# Conferir error_message, guardrail_violations, tool_calls
```

---

## 4. Operações Comuns

### Reset de conversa (debug)

```ruby
conv_id = 1234
AiAgent::ConversationState.where(conversation_id: conv_id).destroy_all
AiAgent::Trace.where(conversation_id: conv_id).destroy_all
```

### Limpar cache de embeddings (após trocar modelo)

```ruby
keys = $alfred.with { |c| c.keys('ai_agent:emb:*') }
$alfred.with { |c| c.del(*keys) } if keys.any?
```

### Reprocessar documento

```ruby
doc = AiAgent::Document.find(<id>)
AiAgent::IngestDocumentJob.perform_later(doc.id)
# o job apaga chunks anteriores e refaz tudo, transacional
```

### Forçar provider específico em runtime (debug)

```ruby
InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER').update!(value: 'openai')
Llm::Config.reset!
# próxima chamada usa OpenAI
```

### Desativar Bea numa conta SEM perder dados

Super Admin → Contas → Configurar Bea → desmarcar **Bea ativa**.
Histórico, traces, documentos e personas ficam intactos.

---

## 5. LGPD / Limpeza de Dados Sensíveis

Se um paciente solicitar remoção:

```ruby
contact_id = <id_do_contact_no_chatwoot>
account_id = <id_da_conta>

# memória de longo prazo
AiAgent::PatientMemory.where(account_id: account_id, contact_id: contact_id).destroy_all

# traces ligados a esse contato
AiAgent::Trace.where(account_id: account_id, contact_id: contact_id).destroy_all

# feedbacks
AiAgent::Feedback.where(account_id: account_id, contact_id: contact_id).destroy_all
```

> Conversation states são por conversation_id, não contact_id direto. Se quiser apagar tudo da conversa, identifique por `Conversation.where(contact_id: ...).pluck(:id)` e apague em cascata.

---

## 6. Limites Conhecidos

| Item | Limite | Onde mudar |
|---|---|---|
| Rate limit por conversa | 60 turnos/hora | `AiAgent::RateLimiter::PER_CONVERSATION_LIMIT` |
| Rate limit por conta | 2000 turnos/dia | `AiAgent::RateLimiter::PER_ACCOUNT_LIMIT` |
| Tamanho máx do PDF | 20 MB | `AiAgent::Document::MAX_PDF_SIZE` |
| História enviada ao LLM | últimas 20 mensagens | `AiAgent::ChatResponseJob::HISTORY_LIMIT` |
| Histórico do paciente | últimos 50 eventos | `AiAgent::PatientMemory::HISTORY_LIMIT` |
| Cache de embeddings | 30 dias | `AiAgent::Llm::EmbeddingClient::CACHE_TTL` |
| Tokens máx/turno (default global) | 4096 | super admin → Limits (em breve UI) |
| Cap mensal de custo | 0 = ilimitado | super admin → Limits |

---

## 7. Onde Encontrar Tudo

| O que | Onde |
|---|---|
| Plano de ação completo | `docs/01-product/ai-agent-action-plan.md` |
| Plugin code | `plugins/ai_agent/` |
| UI super admin | `app/controllers/super_admin/bea_controller.rb` + views |
| Listener integração Chatwoot | `plugins/ai_agent/app/listeners/ai_agent/event_listeners/message_listener.rb` |
| Job principal | `plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb` |
| Tools | `plugins/ai_agent/app/services/ai_agent/tools/` |
| Configuração de provider | `lib/llm/config.rb` + `config/llm.yml` |
| Tabela de preços | `plugins/ai_agent/app/services/ai_agent/pricing.rb` |

---

## 8. Quando Pedir Ajuda

Antes de abrir issue interna, capturar:

```ruby
# id do trace problemático
trace = AiAgent::Trace.find(<id>)
puts trace.attributes.except('tool_calls', 'guardrail_violations').to_yaml
puts "tool_calls: #{trace.tool_calls.inspect}"
puts "violations: #{trace.guardrail_violations.inspect}"

# state da conversa
state = AiAgent::ConversationState.find_by(conversation_id: trace.conversation_id)
puts state&.attributes&.to_yaml

# config global
puts AiAgent::GlobalSetting.current.attributes.to_yaml

# config da conta
puts Account.find(trace.account_id).ai_agent_setting&.attributes&.to_yaml
```
