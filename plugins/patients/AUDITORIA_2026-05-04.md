# 📋 Auditoria #2 — Módulo de Pacientes (pós-refactor)

**Escopo auditado:** `plugins/patients/` + tocando arquivos relacionados em `app/controllers/`, `app/views/api/v1/accounts/patients/`, `spec/`.
**Data:** 2026-05-04
**Origem:** sequela da auditoria anterior (2026-05-03, doc deletado após conclusão). Após 14 rodadas de mudança (12 tabs refatoradas, hardening cross-tenant `#17.1`, migrations rodadas), esta segunda auditoria caça achados **novos** ou **sobreviventes** que escaparam da primeira.
**Método:** 4 agentes paralelos cobrindo backend/security, frontend, performance/DB/specs e código morto. Achados deduplicados.
**Status:** 🟡 **PENDENTE EXECUÇÃO** — 0/55 itens atacados.

> Diferente da primeira auditoria (achados surgicais com bug crítico de exemplo), esta foca em débito **introduzido pelos refactors recentes** ou **gaps que escaparam ao primeiro pente**.

---

## 📈 Score

| Categoria | 🔴 P1 | 🟡 P2 | 🔵 P3 | Total |
|---|---:|---:|---:|---:|
| 🔒 Segurança / dados | 5 | 4 | 2 | **11** |
| 🐢 Performance / queries | 5 | 4 | — | **9** |
| 🧪 Cobertura de testes | 1 | 2 | — | **3** |
| 🎨 Frontend (race/leak/a11y) | 2 | 6 | 4 | **12** |
| 🧹 Refactor leftovers / dead code | — | 7 | 5 | **12** |
| 🏷️ Inconsistência de pattern | — | 4 | 4 | **8** |
| **Total** | **13** | **27** | **15** | **55** |

**Comparação com 1ª auditoria:** 13 P1 + 15 P2 + 5 P3 = 33 itens. Esta rodada tem mais **médios** (refactor leftovers) e menos **críticos** (P1 caiu de 13 → 13 mas focam em *generalizar fixes* feitos em `#17.1` para o resto do plugin).

---

## 🔒 Segurança e dados (11)

### 🔴 P1

1. **`transactions_controller.rb:228, 238, 309`** — `payment_proof` ainda gera URL via `rails_blob_url`, **sem cross-tenant guard**. Mesma classe de bug que motivou `#17.1` para Document/ConsentRecord/ExamMedia, mas o controller financeiro ficou para trás.
   - **Fix:** introduzir `Transaction#payment_proof_signed_url` análogo ao `Document#signed_url`, encodando `account_id` no token.

2. **`secure_blobs_controller.rb:51-52`** — variant é gerada sob demanda com `transformations` decodificadas do token. Mesmo com whitelist de keys do `ActiveStorage::Variant`, valores como `resize_to_limit: [99999, 99999]` consomem CPU/memória do worker (libvips conversion). DoS amplification: 1 GET → 1 conversão pesada.
   - **Fix:** `ALLOWED_TRANSFORMS` whitelist no `SecureBlobTokenService.decode!`, recusando dimensões > 2000px e keys fora de `[:resize_to_limit, :resize_to_fill, :format]`.

3. **`secure_blobs_controller.rb:59`** — `send_data blob.download` carrega blob inteiro em memória sem checar `byte_size`. O comentário cita "max 10MB por config", mas é validação de upload — blobs migrados/legacy podem ter qualquer tamanho.
   - **Fix:** `return head(:payload_too_large) if blob.byte_size > 15.megabytes` antes do `download`.

4. **`audit_logs_controller.rb:3-7`** — `index` não chama `authorize` direto; só o `fetch_patient` chama `authorize @patient, :audit_logs?`. Combinado com `check_authorization { true }` (auto-call desligado), a action depende de `fetch_patient` rodar. Frágil: futuro `skip_before_action :fetch_patient` quebra silenciosamente.
   - **Fix:** chamar `authorize @patient, :audit_logs?` DENTRO de `index`/`export`, não no fetch.

5. **`application_controller.rb:30-37`** — `ensure_session_cookie` roda em **toda request autenticada via token** (after_action), inclusive XHRs cross-origin. Resultado: `Set-Cookie: _chatwoot_session=...` aparece em response de toda API JSON. Antes só era emitido no login. Aumenta superfície de exposição em logs/proxies.
   - **Fix:** filtrar — só renovar se `request.cookies['_chatwoot_session'].present?` (não criar novo em XHR de API).

### 🟡 P2

6. **`secure_blobs_controller.rb:35-38`** — herda direto de `ActionController::Base`, então `protect_from_forgery` está com defaults dúbios. Se alguém adicionar POST/PUT, vai dar erro de CSRF sem token (não vem pelo pipeline do app).
   - **Fix:** `only: [:show]` na rota e/ou `protect_from_forgery with: :null_session`.

7. **`secure_blobs_controller.rb:107-112`** — `decode_token` engole `Tampered`/`Malformed` em 422 silencioso, sem log. Tentativas de forjar token (signal de ataque ou bug de cliente) ficam invisíveis.
   - **Fix:** `Rails.logger.warn` com `request.remote_ip` + classe da exceção. Integrar com `ChatwootExceptionTracker` em produção.

8. **`document.rb:88-90`, `consent_record.rb:164-166`, `exam_media.rb:90-92, 115-117`** — 4 ocorrências de `rescue StandardError; nil`. `signed_url` retorna `nil` em qualquer falha (token gen, route helper sem host, MessageVerifier sem chave). Frontend recebe `url: null` e renderiza `<img>` quebrado sem feedback.
   - **Fix:** `rescue StandardError => e; Rails.logger.error("[#{self.class}#signed_url] #{e.class}: #{e.message}"); nil`.

9. **`exam_folders_controller.rb`, `financial_estimates_controller.rb`, `transactions_controller.rb`** — herdam de `Api::V1::Accounts::BaseController` (não da patients-specific) e **não chamam Pundit**. Cross-tenant é bloqueado por `Current.account.patients.find`, mas não há policy hooks. Inconsistente com o resto do plugin.
   - **Fix:** padronizar herança em `Api::V1::Accounts::Patients::BaseController`, ou adicionar `authorize` explícito em cada action.

### 🔵 P3

10. **`devise_overrides/sessions_controller.rb:120-125` vs `application_controller.rb:34`** — duas estratégias para o mesmo objetivo (escrever warden key): `sign_in(:user, @resource, store: true, bypass: true)` vs `warden.session_serializer.store(user, :user)`.
    - **Fix:** padronizar em `warden.session_serializer.store` (mais low-level e idempotente).

11. **`secure_blob_token_service.rb:90-92`** — `stringify_transformations` só faz `transform_keys(&:to_s)`, não valida shape. Hashes aninhados ou arrays de tamanho arbitrário passam. Combinado com #2, é a porta de entrada do DoS.

---

## 🐢 Performance e queries (9)

### 🔴 P1 — N+1 confirmado em 6 endpoints listados

Padrão: controller faz `.includes(...)` parcial; jbuilder partial chama métodos que disparam queries para attachments/blobs/users. Reproduzível com `?? bullet` em dev.

12. **`consent_records_controller.rb:14-17` + `_consent_record.json.jbuilder:5`** — falta `signature_image_attachment: :blob`. `consent_record.signature_image_url` chama `signature_image.blob.id`. Impacto: 2 queries extras por consentimento.

13. **`exam_medias_controller.rb:15-19` + `_exam_media.json.jbuilder:15-22`** — sem `.includes`. Partial chama `signed_url` (→ `file.blob.id`) + `thumbnail_url` (→ variant) + `uploaded_by.name` por item. **Impacto: ~60 queries extras por página de 20 mídias.**
    - **Fix:** `.includes(:uploaded_by, file_attachment: :blob)`.

14. **`documents_controller.rb:15-20` + `_document.json.jbuilder:20-38`** — sem `.includes`. Partial usa `signed_url` + `generated_by.name` + `signed_by.name`. **Impacto: 4 queries por documento.**
    - **Fix:** `.includes(:generated_by, :signed_by, file_attachment: :blob)`.

15. **`timeline_controller.rb:15-19` + `_event.json.jbuilder:12`** — falta `:actor`. **Impacto: até 50 queries em users/page.**

16. **`transactions_controller.rb:16-30, 308-309, 344`** — itera `serialize_patient_tx`/`serialize_account_tx` que chamam `t.registered_by.name` + `t.payment_proof.attached?`. N+1 em users + active_storage_attachments/blobs.
    - **Fix:** `.includes(:registered_by, payment_proof_attachment: :blob)`.

17. **`patients_controller.rb:11-17` + `_patient.json.jbuilder:39`** — `.includes(:critical_alerts)` é desfeito por `patient.critical_alerts.active.ordered_by_severity` no jbuilder (re-query). Eager load anulado.
    - **Fix:** mover `active.ordered_by_severity` para a associação (`has_many :critical_alerts, -> { active.ordered_by_severity }`) ou filtrar com `select(&:active?)` em Ruby.

### 🟡 P2

18. **`appointments_controller.rb:24-32`** — carrega **todos** os AgendaEvents do paciente sem LIMIT, pagina em Ruby após `.map`. Filtro `(custom_attributes->>'patient_id' = ?) OR (contact_id = ? AND ...)` com OR provavelmente impede uso do índice JSONB criado em `20260503190200`.
    - **Fix:** trocar por `UNION ALL` de duas subqueries indexadas com LIMIT/OFFSET no SQL.

19. **`patient.rb:155-166` (`update_needs_recall`)** — callback `before_save` dispara 2 queries (`patient_appointments.done.first` + `.upcoming.exists?`) **toda vez** que `Patient` é salvo, inclusive em updates triviais (`toggle_recall`).
    - **Fix:** `if: :should_recompute_recall?` ou `if: -> { saved_change_to_<colunas relevantes> }`.

20. **`patients_controller.rb:280-285`** — busca usa `name ILIKE '%foo%'` + `phone LIKE '%digits%'` + `cpf LIKE '%digits%'`. Leading wildcard impede uso de B-tree → seq scan.
    - **Fix (futuro):** `pg_trgm` + GIN trigram em `name`, `phone`, `cpf`. Trade-off: só vale se base passar de ~10k pacientes/account.

21. **`secure_blobs_controller.rb:51`** — `blob.variant(...).processed` a cada GET de thumbnail. Se 2ª request também regenerar (não cacheia), galeria fica lenta.
    - **Fix:** validar com APM. Adicionar `expires_in 1.hour, public: true` no response.

22. **`expire_consent_records_job.rb:28`** — `find_each` sem `.includes(:patient, :account)`. Loop chama `consent.patient` + `consent.account` para timeline → N+1.

---

## 🧪 Cobertura de testes (3)

### 🔴 P1

23. **17 arquivos críticos sem spec.** Listados pelo Agent D:
    - **Services:** `anamnesis_finalizer_service`, `anamnesis_pdf_generator`, `appointment_rescheduler`, `appointment_scheduler`, `clinical_note_signer_service`, `consent_signer`, `document_whatsapp_sender`, `financial_estimate_generator`, `installment_pay_service`, `pdf_generator`, `recall_sender`, `record_pdf_generator`, `session_logger`, `transaction_sync_service`, `treatment_plan_approver`, `treatment_plan_pdf_generator`, `treatment_plan_status_updater`.
    - **Jobs:** `consent_record_purge_job`, `document_purge_job`, `exam_media_purge_job`, `patient_timeline_event_job`, `record_timeline_event_job`, `anamnesis_alert_extractor_job`, `increment_treatment_session_job`, `update_treatment_plan_status_job`.
    - **Controllers:** todos de `api/v1/accounts/patients/*` exceto `secure_blobs`.
    - **Prioridade:** começar por `installment_pay_service` (race condition em double-write `Transaction` + `CashEntry`) e `transaction_sync_service` (refund split fora da transaction em `transactions_controller.rb:163-173`).

### 🟡 P2

24. **`secure_blobs_controller_spec.rb`** — gaps:
    - Sessão warden corrompida (`session['warden.user.user.key'] = "lixo"`) sem teste.
    - `User.find_by` retornando nil para user_id válido (user deletado).
    - `transformations` válidas no token (variant flow) sem teste — só redirect direto e PDF.
    - **Timing attack:** token expirado (410) vs tampered (422) — status diferentes permitem probing de validade. Pelo menos documentar a diferença.

25. **`secure_blob_token_service_spec.rb`** — não testa transformations malformadas (hash aninhado, array gigante) — combinado com #2/#11 isso é a defesa.

---

## 🎨 Frontend — race conditions, leaks, acessibilidade (12)

### 🔴 P1

26. **`Index.vue:201-209`** — `searchTimeout` declarado em escopo de módulo do `<script setup>`, `clearTimeout` só chamado na próxima digitação. Se componente desmonta com timer pendente, dispara `fetchPatients()` em componente unmounted (warning + request órfão).
    - **Fix:** adicionar `onUnmounted(() => clearTimeout(searchTimeout))` (`onUnmounted` já existe em outra linha do arquivo).

27. **`usePhoneContactSearch.js:43-63`** — falta `latestRequestId` (race em busca paralela; resposta lenta sobrescreve resposta rápida). E `phoneContactTimeout` não é zerado em `onBeforeUnmount`.
    - **Fix:** portar pattern `latestSearchId` (já usado em `Index.vue` e `NewPatientModal.vue`) + expor `cleanup()`.

### 🟡 P2

28. **16 modais sem `role="dialog"` / `aria-modal="true"` / focus trap** — todos os modais novos do refactor. `ConfirmDangerModal` (em beclinic_core) já tem o pattern; basta seguir.
    - Lista: `RescheduleModal`, `NoShowModal`, `PayTransactionModal`, `CreateEstimateModal`, `UploadProofModal`, `PrintPreviewModal`, `TreatmentItemModal`, `GenerateDocumentModal`, `SignatureModal`, `ConsentViewModal`, `CameraCaptureModal`, `CreateFolderModal`, `RenameFolderModal`, `DeleteFolderModal`, `LockMediaModal`, `DeleteMediaModal`.

29. **`useFinancialActions.js:81-85`** — `refund` usa `window.confirm` nativo, contradizendo pattern `ConfirmDangerModal` adotado no resto.

30. **`usePatientClinicalGuards.js:20,46`** — recebe `patientId` cru (string) em vez de Ref/getter como demais composables. Quebra contrato de `resolveId()`. Também exporta 4 estados nunca consumidos (`currentAnamnesis`, `isLoaded`, `isLoading`, `hasAnamnesis`) — dead exports.
    - **Fix:** alinhar assinatura + remover exports mortos.

31. **`useNotification.js`** — chamado como `useNotification.error(...)` em 14 arquivos, mas nome `use*` engana (parece composable hook). É objeto-função estático. Linters Vue não detectam mau uso.
    - **Fix:** renomear para `notification.error(...)` ou refatorar para retornar funções via `const { success, error } = useNotification()`.

32. **`useDocuments.js:124-137`** — `remove` exclui sem toast de sucesso (inconsistente com `useExamMedias.remove`).

33. **`EvolutionTab.vue:51-58, 136-192`** — 2 Dialogs do core (delete + erratum) com watchers para sincronizar flags. Frágil: ESC/overlay close depende do `@close` emitir corretamente.
    - **Fix:** substituir por `ConfirmDangerModal` (já existente).

### 🔵 P3

34. **`PatientNavSidebar.vue:41,61`, `PatientCriticalAlertPopup.vue:33`, `Index.vue:309-315`** — botões icon-only sem `aria-label`. Leitores de tela leem só "button".

35. **Constantes `BRT = 'America/Sao_Paulo'` duplicadas em 6 arquivos** — `Record.vue:52`, `consentTemplates.js:15`, `constants/audit.js:8`, `constants/timeline.js:6`, `constants/procedures.js:7`, `constants/financial.js:134`.
    - **Fix:** mover para `beclinic_core/dateHelpers.js` (que já tem helpers BRT).

36. **`constants/financial.js:13` + `constants/treatmentPlan.js:10`** — `TX_STATUS_CONFIG`, `ESTIMATE_STATUS_CONFIG`, `TX_FILTER_OPTIONS`, `ITEM_STATUS_CONFIG` são `export`adas mas só usadas internamente pelos helpers do mesmo arquivo.
    - **Fix:** remover `export`.

37. **`usePatientClinicalNotes.js:17`** — `EMPTY_NOTE` em escopo de módulo. `blankNote = () => ({ ...EMPTY_NOTE })` deveria ficar dentro da função (factory por instância).

---

## 🧹 Refactor leftovers / código morto (12)

### 🟡 P2

38. **2 composables ainda usam `useAlert` em vez de `useNotification`:**
    - `usePatientClinicalNotes.js:3` (9 call-sites em l.57,65,103,107,117,124,177,183,190) — afeta toasts da aba Evolução.
    - `usePatientSummary.js:2,104,137` — afeta `Record.vue` e `Index.vue`. Mensagens em pt-BR cru (não migradas pra i18n).

39. **3 padrões de delete modal coexistem:**
    - `ConfirmDangerModal` (canônico): TreatmentPlanTab, ProceduresTab, DocumentsTab.
    - `<Dialog ref type="alert">` do core: EvolutionTab (2 inline).
    - **Tailwind hand-rolled (sem reuso):** `DeleteMediaModal.vue`, `DeleteFolderModal.vue`, `LockMediaModal.vue` em `exams-tab/`.
    - **Fix:** unificar nos 3 do exams-tab para `ConfirmDangerModal`.

40. **Endpoint `documents/attach`** — `routes.rb:220` + `documents_controller#attach:71` existem, mas frontend não chama (`grep "documents/attach" plugins/patients/frontend` → 0). Decidir: implementar UI ou remover.

41. **Endpoint `exam_medias/compare`** — `routes.rb:209` + `exam_medias_controller#compare:105` existem; frontend não chama.

42. **Endpoint `patients/:id/quick_action`** — `routes.rb:150` + `patients_controller#quick_action:200`; frontend não chama.

43. **Duas árvores SCSS coexistindo:** `Record.vue:2-3` importa tanto `styles/record/_*-tab.scss` (10 partials, 1490 linhas) quanto `styles/tabs/_*Tab.scss` (10 partials, 3980 linhas). Classes como `.consent-kpi-card`, `.consent-canvas`, `.consent-audit-*` estão **definidas em ambas**.
    - **Fix:** auditar par a par e ficar com `tabs/` (provavelmente canônico). ~1500 linhas a remover.

44. **Comentários `# Roadmap #17.1 ✅` em 6 arquivos backend** — `consent_record.rb`, `document.rb`, `exam_media.rb`, etc. Item já fechou em produção; referência ao número de roadmap é arqueologia.
    - **Fix (cosmético):** simplificar para `# Cross-tenant guard via SecureBlobsController`.

### 🔵 P3

45. **Export morto — `formatRgDisplay`** (`registrationMasks.js:90`) — alias de `maskRg`. Zero importadores. ROADMAP linha 79 já dizia "removido", mas o `export` ficou.

46. **Export morto — `DocumentsAPI.create`** (`api/patients/documents.js:17-19`) — backend não tem rota `POST /documents` (só `:generate`/`:attach`).

47. **Exports mortos — `ConsentsAPI.getPending` e `.delete`** (`api/patients/consents.js:15-17, 49-51`) — backend não expõe esses endpoints (rotas são `[:index, :create, :show]` + members `sign|send_remote|revoke`).

48. **`getInitials` duplicado em 3 lugares:**
    - `utils/registrationMasks.js:103` (export, usado por AvatarUploadCard).
    - `utils/patientFormatters.js:83` (export, usado por PatientProfileBanner).
    - `audit-tab/AuditLogsTable.vue:37` (função local).
    - **Fix:** consolidar em `patientFormatters.js`.

49. **`MediaLightbox.vue:25-33`** — botão de download é `<a class="...">` cru ao lado de um `<BeclinicButton>`. 2 estilos lado a lado para fechar/baixar.

---

## 🏷️ Inconsistência de pattern (8)

### 🟡 P2

50. **`BeclinicButton` quase não foi adotado nos 12 tabs:** `grep "BeclinicButton"` retorna **4 arquivos**; `grep "<button[^>]*class="` retorna **58 arquivos**. ROADMAP marcou "CSS dead code cleanup ✅" mas só removeu **classes SCSS** legadas — o HTML continua nativo.
    - **Decisão necessária:** completar adoção do BeclinicButton (pass adicional) OU aceitar `<button>` como pattern e fechar formalmente. Ambíguo agora.

51. **i18n incompleto — 12 arquivos com `<!-- eslint-disable @intlify/vue-i18n/no-raw-text -->`:**
    - `general-tab/*.vue` (5 arquivos: GeneralTab, GeneralAccountDataCard, GeneralActiveTreatmentCard, GeneralClinicalTagsCard, GeneralConsultationJourneyCard).
    - `record/*.vue` (5 arquivos: PatientHeaderActions, PatientNavSidebar, PatientCriticalAlertPopup, PatientArchivedBanner, PatientProfileBanner).
    - **Fix:** criar namespaces `PATIENT_GENERAL.*` e `PATIENT_RECORD.*`.

52. **`FormSelect` vs `<select>` nativo** — não auditei sistematicamente, mas a 1ª auditoria fechou os call-sites principais. Vale uma varredura adicional.

53. **`Current.account` vs `current_account`** — 1ª auditoria fechou no plugin patients (39 ocorrências em 6 arquivos). Mas houve crescimento de código desde então (controllers novos do refactor); confirmar que não regrediu.

### 🔵 P3

54. **2 controllers patients herdando de bases diferentes** — `Api::V1::Accounts::Patients::BaseController` (auto-call de `check_authorization`) vs `Api::V1::Accounts::BaseController` (não). Já listado em #9 acima.

55. **Comentários TODO/FIXME órfãos** — não enumerei. Sugestão: `grep -rn "TODO\|FIXME\|HACK\|XXX" plugins/patients/app` e revisar.

---

## 🎯 Sequência sugerida de ataque

**Sprint 1 — segurança crítica (0.5–1 dia):**
- #1 (`payment_proof` cross-tenant guard) — replicar pattern de `Document#signed_url`.
- #2 + #11 (whitelist de transformations no token).
- #3 (limite de byte_size no `send_data`).
- #4 (authorize explícito em audit_logs).

**Sprint 2 — N+1 em endpoints listados (0.5 dia):**
- #12 a #17 (6 N+1 confirmados, fix é só `.includes(...)` no controller). Ganho imediato de latência.

**Sprint 3 — refactor leftovers / consistência (1 dia):**
- #38 (migrar 2 composables `useAlert` → `useNotification`).
- #39 (unificar 3 modais Tailwind do exams-tab para `ConfirmDangerModal`).
- #40-#42 (decidir destino dos 3 endpoints órfãos).
- #45-#48 (limpar 3 exports JS órfãos + getInitials duplicado).
- #51 (i18n dos 12 arquivos faltantes — `general-tab` + `record/`).

**Sprint 4 — performance secundária (1–2 dias):**
- #18 (appointments — UNION ALL).
- #19 (Patient#update_needs_recall com guard).
- #21 (validar cache de variants — APM/manual).
- #22 (eager-load no ExpireConsentRecordsJob).

**Sprint 5 — débito de testes (2–3 dias):**
- #23 priority list: `installment_pay_service`, `transaction_sync_service`, `secure_blobs_controller` gaps (#24).

**Decisão de produto / escopo maior:**
- #50 (BeclinicButton adoption pass).
- #20 (pg_trgm para busca de pacientes).
- #43 (consolidar 2 árvores SCSS).
- Demais P3 cosméticos.

**Total estimado:** 4–7 dias para fechar 80% (Sprints 1-3 + parte de 4). Sprints 4-5 + decisões de produto = +5–8 dias. Para 100%, ~10–15 dias.

---

## 📦 Como esta auditoria foi gerada

4 agentes paralelos, cada um com escopo definido:
- **Backend security:** controllers, models, services, jobs, policies, novo `SecureBlobsController`.
- **Frontend code quality:** composables, sub-componentes, utils.
- **Refactor leftovers:** dead code, exports órfãos, inconsistências, CSS duplicado, endpoints sem caller.
- **Performance + DB + spec gaps:** N+1 (com leitura controller+jbuilder), queries lentas, migrations, cobertura de testes.

Achados deduplicados quando apareceram em mais de um agente (ex: `useAlert` sobrevivente foi flagged por B e C — listado uma vez em #38).

**Não foi auditado nesta rodada:**
- Front-end fora do plugin patients (Chatwoot core, beclinic_core, beclinic_admin, financial).
- Backend fora do plugin patients (exceto arquivos diretamente relacionados: `application_controller.rb`, `devise_overrides/sessions_controller.rb`).
- Specs end-to-end (Cypress / Playwright).
- Lighthouse / bundle size / Vue devtools profiler.

Para próxima auditoria, considerar incluir esses escopos.
