# ADR 0001 — LLM Provider Fallback + Circuit Breaker

**Status:** Accepted — 2026-05-19
**Plugin:** `ai_agent`
**Arquivos:** [chat_service.rb](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb), [chat_service/circuit_breaker.rb](../../plugins/ai_agent/app/services/ai_agent/chat_service/circuit_breaker.rb)

## Contexto

Bea depende de LLM externo (Gemini 3 Flash ou OpenAI gpt-4.1-mini) pra gerar respostas. Ambos providers têm:

1. **Falhas transitórias**: rate limits, 503 "high demand" (Gemini frequente), `ForbiddenError` em rotação de API key
2. **Outages**: Gemini caiu 4× em 1 semana durante piloto (dezembro 2025). OpenAI mais estável mas custa 3-5× mais por token
3. **Latência**: cada retry adiciona 2-3s ao turn → paciente percebe lag

Sem estratégia explícita, a opção era:
- (a) Crashar o job em falha transitória → reply nunca chega ao paciente (UX péssimo, retry manual)
- (b) Retry no mesmo modelo indefinidamente → cost runaway + latência cumulativa

## Decisão

**Fallback automático + circuit breaker Redis-based:**

1. Tenta `primary` (model configurado via `CAPTAIN_LLM_PROVIDER`)
2. Se falha com `RubyLLM::{RateLimit,Server,Forbidden,ServiceUnavailable}Error` E há OpenAI fallback configurado:
   - Tenta `openai_fallback_model` 1× — retorna `used_fallback: true` no Trace
3. Se NÃO há fallback OU também falha: retry 1× no primary com **jitter** (`2s + rand×1.5s`) — evita thundering herd
4. **Circuit breaker** (BE-24, lote 40): se primary falhou ≥5 vezes em 60s, abre circuit → próximas requests pulam direto pro fallback (sem latência do primary failing). Cooldown 5min via TTL no Redis.

## Consequências

### Positivas

- **0% de paciente sem resposta** por falha transitória single-provider
- **Métricas**: Trace registra `provider` real usado (não o configurado) — dashboards detectam outages do primário
- **Cost cap consciente**: `ConfigResolver.over_monthly_cost_cap?` checked ANTES do retry — fallback caro não bypassa o teto
- **Sem código pra cada provider**: `RubyLLM.chat(model:)` abstrai. Adicionar Anthropic seria 1 linha no `case provider`

### Negativas / trade-offs

- **Duplicação de custo durante fallback**: se Gemini falhar e OpenAI responder, paga 2 chamadas (1 retornou erro, 1 retornou content) — aceitável vs UX de "Bea não respondeu"
- **Circuit breaker é per-process / per-Redis**: workers Sidekiq compartilham via Redis (correto), mas dev env sem Redis = circuit sempre fechado (fail-open OK)
- **Sem health check ativo do primary**: circuit só fecha após N falhas reais. Cold start após outage longo paga as primeiras 5 falhas pra reabrir o circuit

## Alternativas consideradas

| Opção | Por que NÃO |
|---|---|
| Retry exponencial no mesmo provider só | Cost runaway, latência cumulativa, não resolve outages reais (>1h) |
| Round-robin entre providers | Hard cap em consistência: paciente recebe resposta de qualidade variável. Bea precisa de tom consistente |
| Provider switching por usuário | Complexidade alta, ganho mínimo — usuário não escolhe LLM |
| Sidekiq retry com fail-loud | Reply ao paciente fica em hold por minutos. UX inaceitável pra WhatsApp |

## Migração futura

- Adicionar Anthropic Claude como 3º provider — 1 linha no `model_for_provider`
- Health check ativo (ping LLM a cada 5min) pra fechar circuit proativamente — não prioridade no piloto
- Per-account provider override (já existe via `AccountSetting.chat_model`) — alguma clínica grande pode preferir OpenAI exclusivo
