# ADR 0002 — Sentinel LLM-as-Judge é Opt-In

**Status:** Accepted — 2026-05-19
**Plugin:** `ai_agent`
**Arquivos:** [humanization/sentinel.rb](../../plugins/ai_agent/app/services/ai_agent/humanization/sentinel.rb), [chat_service.rb#run_sentinel](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb)

## Contexto

Após o LLM primário gerar a resposta, em **turnos high-stakes** (book, reschedule, emergência, info clínica) queremos uma segunda passada que avalie se a resposta:

- Não viola guardrails (medical diagnosis, prescription) — já coberto pelo `Guardrail::Validator` determinístico
- Não tem hallucinations (citou data/hora inexistentes no tool log, professional name divergente, etc) — exige outro LLM
- Mantém tom da Bea (não saiu do personagem, não vazou system prompt) — exige outro LLM

Isso é o pattern **"LLM-as-judge / Reflection 1-step"**.

Custo: cada turn high-stakes paga **2× LLM calls** (1 pra gerar + 1 pra julgar). Em piloto com tráfego baixo é OK; em escala (1000+ contas) o budget mensal dobra nos paths mais caros.

## Decisão

**Sentinel é OPT-IN via `InstallationConfig['CAPTAIN_BEA_SENTINEL_ENABLED'] = 'true'`. Default `false`.**

Mesmo quando ativado:

1. Sentinel SÓ roda em turnos classificados como **high-stakes** pelo `HighStakesDetector` (tool calls específicos: book, reschedule, emergência detectada)
2. Sentinel respeita o cost cap mensal (SEC-24, lote 16): `AiAgent::ConfigResolver.over_monthly_cost_cap?` checked antes da chamada
3. Sentinel input passa por `sanitize_for_judging` (SEC-24): remove instruções de prompt injection ecoadas pela Bea
4. Verdict do Sentinel vai pro `Trace.guardrail_violations` como `sentinel:ok` / `sentinel:reproved:<reason>` — **NÃO regenera resposta** no piloto, apenas telemetria

## Consequências

### Positivas

- **Custo previsível em piloto**: turnos triviais (saudação, "qual o telefone") não pagam o tax do Sentinel
- **Cost cap absoluto**: mesmo accounts com Sentinel ativado não estouram o teto mensal
- **Observabilidade primeiro**: dashboards mostram `sentinel:reproved:*` por categoria antes de ativar regeneration
- **Reversível**: super admin desativa via InstallationConfig sem deploy

### Negativas / trade-offs

- **Hallucinations passam em accounts com Sentinel off** (a maioria no piloto). Mitigação: `Guardrail::Validator` determinístico cobre medical diagnosis + prescription (categorias mais críticas); telemetria via Trace mostra escalations
- **Decisão de ativar fica com cada super admin** — não há push automático. Adopt rate baixo no início

## Alternativas consideradas

| Opção | Por que NÃO |
|---|---|
| Sentinel sempre on | 2× custo LLM em escala. Piloto não suporta orçamento |
| Sentinel auto-regenerate resposta | Sem telemetria primeiro, regeneration cega pode degradar respostas boas — Goodhart |
| Validação só com guardrails determinísticos | Hallucinations de tool calls (data/hora inexistente) escapam — exige LLM ler tool_log |
| Per-account opt-in (em vez de installation-level) | Complexidade UI sem demanda — super admin global atende piloto |

## Migração futura (Sprint H/I)

- **Dashboard de Sentinel verdicts** — visualizar `sentinel:reproved:*` por categoria, identificar padrões
- **Per-account toggle** se algum cliente exigir compliance específico
- **Sentinel regeneration** (atualmente só telemetria) quando dados confirmarem que `sentinel:reproved` correlaciona com escalation real
- **Custo via cost cap dedicado** — separar budget Sentinel do budget LLM principal pra accounts grandes
