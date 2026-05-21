> [!IMPORTANT]
> **Nota de Auditoria Arquitetural:**
> O módulo de Migração vive 100% isolado em `plugins/migration/` (Rails Engine). A única exceção são os pontos de integração com o painel SuperAdmin (controller, view, navegação, route) — necessários porque a feature é exposta dentro do Administrate, que é parte do core. Esses pontos são listados explicitamente em "Arquivos do Core" abaixo.
> Para a topologia geral do plugin no sistema, ver `02-architecture/system-architecture.md`.

# Plano de Ação — Módulo de Migração (Clinicorp → Klivy)

## 1. Visão Geral

Importador autônomo, executado pelo Super Admin, que recebe planilhas exportadas da Clinicorp e popula a conta do cliente no Klivy: **pacientes, anamneses e agenda**. O processamento é assíncrono (Sidekiq), idempotente por linha quando possível, e nunca silencia erros — toda divergência vira log estruturado em `MigrationRun#errors_log`.

Hoje suporta dois fluxos:

- **Pacientes (+ anamnese opcional)** — aceita até 3 CSVs no mesmo upload (`Patient.csv` obrigatório, `PatientAnamnesis.csv` e `Anamnesis.csv` opcionais). Reaproveita o passe de pacientes pra construir o índice de IDs e linkar as anamneses na sequência.
- **Agenda** — CSV único de eventos/appointments (`Appointment.csv`), com inferência de status, criação automática de `AgendaService` por procedimento, e mapeamento de "Categoria" como `AgendaCustomAttribute` do tipo `select` (dropdown).

Em "breve" no UI: importação financeira (transações/parcelas) — selector já reservado mas desabilitado.

## 2. Arquitetura

### 2.1 Localização

```
plugins/migration/
├── lib/
│   ├── migration.rb                     # entry-point do plugin
│   └── migration/engine.rb              # Rails Engine (auto-load + migrations)
├── db/migrate/
│   └── 20260426023750_create_migration_runs.rb
├── app/
│   ├── models/migration_run.rb          # KINDS, STATUSES, progress_percent
│   ├── jobs/migration/process_csv_job.rb
│   └── services/migration/
│       ├── clinicorp_patient_importer.rb   # pacientes + anamnese
│       └── clinicorp_agenda_importer.rb    # agenda
└── frontend/features/migration/
    ├── MigrationIndex.vue               # tela principal
    ├── api/migrationApi.js              # fetch wrapper
    └── components/MigrationUploadForm.vue   # form de upload
```

### 2.2 Fluxo

1. Super Admin acessa **Migração** no menu lateral do `/super_admin`.
2. Seleciona conta de destino + tipo (Pacientes/Agenda) + arquivos.
3. `SuperAdmin::MigrationsController#create` valida tamanho (≤25MB cada), lê os bytes em UTF-8 e cria um `MigrationRun` com `status=pending`.
4. Enfileira `Migration::ProcessCsvJob` na fila `:low` do Sidekiq.
5. Job marca `processing`, chama o importer correspondente, atualiza `processed_rows / created_count / updated_count / skipped_count / error_count` em batches via `update_columns` (sem callbacks).
6. UI faz polling do `GET /super_admin/migrations/:id.json` pra mostrar progresso.

### 2.3 Tabela `migration_runs`

```sql
id                          bigint pk
account_id                  bigint  -- destino
kind                        string  -- 'patients' | 'agenda' | 'financial'
source                      string  -- 'clinicorp' | 'generic'
status                      string  -- 'pending' | 'processing' | 'completed' | 'failed'
csv_filename                string
total_rows                  integer
processed_rows              integer
created_count               integer
updated_count               integer
skipped_count               integer
error_count                 integer
errors_log                  jsonb   -- últimos 200 erros: [{line, level, message}]
error_message               text    -- erro fatal (run inteira falhou)
started_at                  timestamp
finished_at                 timestamp
triggered_by_super_admin_id bigint
created_at, updated_at      timestamp
```

`progress_percent` é derivado de `processed_rows / total_rows`.

## 3. Importador de Pacientes — `ClinicorpPatientImporter`

### 3.1 Mapeamento de Colunas Clinicorp → Klivy

| Coluna Clinicorp | Campo Patient | Notas |
|---|---|---|
| `Name` | `name` | obrigatório |
| `NickName` | (preservado em `additional_attributes`) | — |
| `BirthDate` | `birthdate` | parse ISO; **fix timezone**: ancorado em meio-dia local pra não cair pro dia anterior |
| `Sex` | `sex` (enum) | `M/F/Masc/Fem/...` → `masculino/feminino` |
| `CivilStatus` | `marital_status` (enum) | `SINGLE/MARRIED/DIVORCED/WIDOWED` (em pt-BR também) |
| `Email` | `email` | validado contra `URI::MailTo::EMAIL_REGEXP` |
| `MobilePhone` ou `Landline` | `phone` | normalizado pra `+55XXXXXXXXXXX` |
| `OtherDocumentId` (11 dígitos numéricos) | `cpf` | heurística: 11 dígitos = CPF |
| `DocumentId` | `rg` | RG livre |
| `Address`, `AddressNumber`, `AddressComplement`, `Neighborhood`, `City`, `state`, `Zip` | `address` jsonb | concatenados em hash |
| `insurancePlanName`, `insurancePlanNumber` | `insurance` jsonb | — |
| `PersonInCharge` | `emergency_contact` jsonb | `{name: ...}` |
| `Notes` + `IndicationSource` | `pinned_note` | concatenados com " — " (preserva contexto clínico) |
| `id` (16 dígitos exato) | índice em memória | usado pra linkar anamneses |

### 3.2 Deduplicação (Match + Merge por Score)

Cada linha do CSV passa por:

1. **Match por CPF** (mais forte). Se achar, segue pro merge.
2. **Match por nome normalizado** (case + accent fold) dentro da mesma `account_id`, ignorando soft-deletes.
3. Se não achar nenhum, **cria** novo `Patient` com `origin: 'migration_clinicorp'`.

Quando há match, decide qual versão fica via **score de campos populados**:

```ruby
PATIENT_FIELDS = [:name, :email, :phone, :cpf, :rg, :birthdate, :sex, :marital_status]
# +1 ponto pra cada campo presente
# +1 ponto pra cada chave populada em address/insurance/emergency_contact
```

- Se `incoming_score > existing_score` → atualiza, **mas só preenche campos vazios** do existing (nunca destrói dado já populado).
- Senão → skip + log: `"Já existe paciente 'X' (id=Y) com mais ou igual informação."`

### 3.3 Linkagem de Anamneses (truncamento Excel)

Os CSVs da Clinicorp foram exportados via Excel, que **arredondou os IDs de 16 dígitos pra notação científica** (`5025635697819648` virou `5,02564E+15`) — perda irrecuperável de precisão. Apenas o `Patient.csv` carrega o `id` exato; `PatientAnamnesis.csv` e `Anamnesis.csv` só têm a forma truncada.

Solução: **processar os 3 CSVs no mesmo run**. Durante o passe de pacientes construímos um índice em memória `{ id_exato → patient_id, id_truncado → patient_id }`. No passe de anamneses, cada `PatientId` truncado é resolvido via esse índice.

Se duas IDs exatas truncarem pra mesma chave, é registrada **colisão** e as anamneses dessa chave são bloqueadas (nunca atribuídas por chute).

A função `scientific_truncation` replica o arredondamento half-up do Excel (5 casas decimais, 6 dígitos significativos):

```ruby
# 5025635697819648 → "5,02564E+15"
# 4510552819367936 → "4,51055E+15"
exp = digits.length - 1
first7 = digits[0, 7].to_i
rounded6 = (first7 + 5) / 10  # half-up
# overflow handling: 9999995 → 1000000 bumpa o expoente
```

Validada contra **30 pares reais** dos CSVs do cliente: 30/30.

### 3.4 Mapeamento Q/A → Anamnesis

A Clinicorp armazena anamneses como uma lista linear de pares `{Question, AnswerOption (Sim/Não), AnswerDescription (texto livre)}`. Nosso modelo `Anamnesis` tem campos estruturados (`medical_history` jsonb, `allergies` jsonb, `pregnancy` jsonb, `relevant_habits` jsonb, `chief_complaint` text, etc).

A constante `ANAMNESIS_QUESTION_MAP` no importer faz o roteamento por **substring case-insensitive**:

| Pergunta Clinicorp (substring) | Campo Anamnesis | Forma |
|---|---|---|
| `motivo da consulta` | `chief_complaint` | text |
| `tratamento médico` / `corta, sangra muito` / `problema cardíaco` / `desmaio` / `pressão arterial` | `medical_history` | `{pergunta => {yes, details}}` |
| `tomando algum medicamento` | `current_medications` | `[{name}]` |
| `alergia a algum medicamento` | `allergies` | `[{description, severity}]` |
| `reação a anestesia` | `contraindications` | `[descricao]` |
| `range os dentes` / `algum hábito` / `fuma` | `relevant_habits` | `{pergunta => valor}` |
| `diabético` | `family_history` | text |
| `grávida` | `pregnancy` | `{is_pregnant, details}` |
| `último tratamento odontológico` / `sensibilidade nos dentes` / `rotina de higiene` / `usa fio dental` / `gengiva sangra` / `dores de cabeça` | `additional_notes` | linha `Pergunta: Resposta` |

> **Regra de ouro:** qualquer pergunta que NÃO casar nenhum padrão acima cai automaticamente em `additional_notes` (observações confidenciais), formatada como `"Pergunta: Resposta"` linha a linha. Nada é silenciosamente descartado.

Cada `Anamnesis` criada é marcada com `status=finalized`, `finalized_at=now`, `version_number=1`, `professional_id=nil` (importada, sem dentista atribuído).

## 4. Importador de Agenda — `ClinicorpAgendaImporter`

### 4.1 Mapeamento de Colunas

| Coluna Clinicorp | Campo AgendaEvent | Notas |
|---|---|---|
| `id` | `custom_attributes.external_id` | preserva pra re-imports idempotentes |
| `date` + `fromTime` + `toTime` | `starts_at`, `ends_at` | timezone `America/Sao_Paulo`, atravessa meia-noite OK |
| `PatientName` | `title` + `custom_attributes.patient_name` | **fix**: antes era o nome do serviço |
| `DentistName` | `user_id` | resolvido via `User.where(account_id).find { name match }` (case+accent fold) |
| `Procedures` | `AgendaService` | **só cria service se Procedures não-vazio**; senão treatment fica nulo (UI mostra "Selecione o tratamento") |
| `Status` / `Canceled` / `Deleted` | `status` (enum) | mapa abaixo |
| `Notes` | `description` | livre |
| `MobilePhone` | `custom_attributes.patient_phone` | display no modal |
| `CategoryDescription` | `AgendaCustomAttribute` "Categoria" | criado como `field_type='select'` (dropdown) |

### 4.2 Mapa de Status

```ruby
STATUS_MAP = {
  '' / 'SCHEDULED' / 'PENDING' => 'scheduled',
  'CONFIRMED' / 'CONFIRMADO'   => 'confirmed',
  'ARRIVED' / 'CHECKED_IN'     => 'arrived',
  'IN_PROGRESS' / 'STARTED'    => 'in_progress',
  'ATTENDED' / 'COMPLETED' / 'DONE' / 'FINISHED' => 'completed',
  'NO_SHOW' / 'MISSED'         => 'no_show',
  'CANCELED' / 'CANCELLED'     => 'cancelled'
}
# override: se Canceled=X ou Deleted=X → 'cancelled'
```

### 4.3 Categoria como Dropdown (AgendaCustomAttribute)

No primeiro passe, coleta todos os valores únicos de `CategoryDescription` no CSV. Cria (ou atualiza) um `AgendaCustomAttribute` chamado "Categoria" com:

```ruby
field_type: 'select'
options: 'Endodontia,Ortodontia,Estética,Restauração,...'  # union dos valores existentes + novos
position:  AgendaCustomAttribute.where(account_id).count
```

Em re-imports, **preserva opções existentes** e adiciona apenas as novas. Cada `AgendaEvent` referencia a categoria via `custom_attributes["attr_<id>"]`, que é como o `AgendaEventModal` renderiza atributos personalizados.

### 4.4 AgendaService Auto-Criado

Quando `Procedures` está preenchido e ainda não existe um `AgendaService` com aquele nome (case-insensitive), cria um com:

```ruby
duration_minutes: 60         # default — dentista ajusta depois
color: SERVICE_COLOR_PALETTE.sample  # 17 cores Tailwind, distribuição aleatória
position: AgendaService.where(account_id).count
```

Usa cache em memória (`@service_cache[normalized_name]`) pra não bater no banco a cada linha.

### 4.5 Modal Display Fields

O `AgendaEventModal` no frontend lê os seguintes campos de `custom_attributes` (via `useAgendaCrud.js`):

```javascript
patient_name      // mostrado como título no modal (fallback: event.title)
patient_phone     // botão de WhatsApp
patient_avatar_url
patient_id        // link pro prontuário
service_id        // pré-seleciona dropdown de tratamento
service_name
treatment         // mesma coisa que service_name (legado)
priority          // 'medium' default
```

Importer popula tudo isso no `custom_attributes` do `AgendaEvent`.

## 5. Arquivos do Plugin (`plugins/migration/`)

| Arquivo | Função | Status |
|---|---|---|
| [`lib/migration.rb`](../../../plugins/migration/lib/migration.rb) | Entry-point do plugin (require engine) | Criado nesta migração |
| [`lib/migration/engine.rb`](../../../plugins/migration/lib/migration/engine.rb) | Rails Engine; injeta `Account.has_many :migration_runs`; registra path de migrations | Criado |
| [`db/migrate/20260426023750_create_migration_runs.rb`](../../../plugins/migration/db/migrate/20260426023750_create_migration_runs.rb) | Schema da `migration_runs` | Criado |
| [`app/models/migration_run.rb`](../../../plugins/migration/app/models/migration_run.rb) | Model com `KINDS`, `STATUSES`, `mark_processing!/completed!/failed!`, `progress_percent` | Criado |
| [`app/jobs/migration/process_csv_job.rb`](../../../plugins/migration/app/jobs/migration/process_csv_job.rb) | Roteia por `kind`; aceita payload `String` (legado, agenda) ou `Hash` (novo, pacientes 3 CSVs) | Criado, depois ampliado pra aceitar Hash |
| [`app/services/migration/clinicorp_patient_importer.rb`](../../../plugins/migration/app/services/migration/clinicorp_patient_importer.rb) | Importador de pacientes + anamneses | Criado, depois reescrito pra aceitar 3 CSVs e linkar anamneses via truncamento |
| [`app/services/migration/clinicorp_agenda_importer.rb`](../../../plugins/migration/app/services/migration/clinicorp_agenda_importer.rb) | Importador de agenda | Criado; várias iterações de fix (patient_name, treatment, Categoria como select, service auto-create condicional) |
| [`frontend/features/migration/MigrationIndex.vue`](../../../plugins/migration/frontend/features/migration/MigrationIndex.vue) | Tela principal (lista de runs + form) | Criado |
| [`frontend/features/migration/api/migrationApi.js`](../../../plugins/migration/frontend/features/migration/api/migrationApi.js) | `uploadCsv` aceita `{file}` (single) ou `{files: {patients, patientAnamnesis, anamnesis}}` (multi) | Criado, depois ampliado |
| [`frontend/features/migration/components/MigrationUploadForm.vue`](../../../plugins/migration/frontend/features/migration/components/MigrationUploadForm.vue) | Form com 1 ou 3 file pickers conforme tipo | Criado, depois ampliado |

## 6. Arquivos do Core (Exceções Justificadas)

| Arquivo | Motivo da exceção |
|---|---|
| [`app/controllers/super_admin/migrations_controller.rb`](../../../app/controllers/super_admin/migrations_controller.rb) | SuperAdmin usa Administrate (gem), que precisa que controllers vivam no namespace `SuperAdmin::` carregado pelo core. Refatorado para multiplexar entre `handle_patients_create` (3 arquivos) e `handle_single_file_create` (legado). |
| [`app/views/super_admin/migrations/index.html.erb`](../../../app/views/super_admin/migrations/index.html.erb) | View de mount do componente Vue dentro do Administrate. |
| [`app/views/super_admin/application/_navigation.html.erb`](../../../app/views/super_admin/application/_navigation.html.erb) | Item "Migração" na sidebar do Administrate; também excluiu `migrations` do auto-nav genérico. |
| [`app/javascript/entrypoints/superadmin_pages.js`](../../../app/javascript/entrypoints/superadmin_pages.js) | Registro do `MigrationIndex` no entrypoint Vue do SuperAdmin. |
| [`config/routes.rb`](../../../config/routes.rb) | `resources :migrations, only: [:index, :create, :show]` dentro do namespace `super_admin`. |

> **Por que não dá pra mover esses pro plugin:** Administrate carrega controllers e views por convenção de path absoluto (`app/controllers/super_admin/...`). Mover quebra a discovery. A solução de longo prazo é envelopar `SuperAdmin::MigrationsController` num concern dentro do plugin e fazer o controller do core delegar — fora do escopo desta entrega.

## 7. Bugs Corrigidos Durante a Construção

Bugs descobertos pelo cliente em testes reais e corrigidos durante esta entrega:

| Bug | Arquivo | Fix |
|---|---|---|
| Paciente sumindo da lista quando havia >500 (planilha tinha 2.389) | `plugins/patients/frontend/api/patients/index.js:30` + `plugins/patients/app/controllers/api/v1/accounts/patients_controller.rb:302` | Limite `per_page=500` → `per_page=50000` no front e cap 500 → 50.000 no backend |
| Data de nascimento aparecia 1 dia antes (timezone) | `plugins/patients/frontend/routes/patients/Record.vue:4412` + `plugins/patients/frontend/routes/patients/Index.vue:23` | `formatDate` ancora `YYYY-MM-DD` em `T12:00:00` local antes de criar Date (evita conversão UTC pro dia anterior) |
| Nome do evento aparecia "Odonto" em vez do nome do paciente | `clinicorp_agenda_importer.rb` | `title = patient_name` (antes era `service.name`) |
| Tratamento aparecia "Odonto" mesmo quando Procedures vazio | `clinicorp_agenda_importer.rb` | `service` só é criado se `Procedures.present?`; treatment fica nulo senão |
| Categoria importada como texto livre em vez de dropdown | `clinicorp_agenda_importer.rb` | `AgendaCustomAttribute` criado com `field_type: 'select'`, opções coletadas dos valores únicos do CSV |
| Re-imports sobrescrevendo opções de Categoria | `clinicorp_agenda_importer.rb` | Union entre opções existentes e novas (`existing | values`) |

## 8. Operações de Suporte (Scripts em `/tmp/`)

Scripts de utilidade criados durante a construção (não fazem parte do plugin, ficam só pro debug do dev):

| Script | Função |
|---|---|
| `/tmp/wipe_all.rb` | Limpa conta inteira: AgendaEvent, AgendaService, AgendaCustomAttribute, Patient (com Contact órfãos), Anamnesis, MigrationRun. Usado pra resetar entre testes. |
| `/tmp/wipe_agenda.rb` | Limpa só agenda (eventos, services, atributos, runs de agenda). |
| `/tmp/inspect_agenda.rb` | Lista AgendaEvents da conta com estatísticas mensais. |
| `/tmp/check_runs.rb` | Lista últimas 10 MigrationRuns com erros. |
| `/tmp/list_anamneses.rb` | Lista pacientes da migração com anamnese preenchida + resumo dos campos. |
| `/tmp/validate_trunc.rb` | Valida `scientific_truncation` contra 30 pares reais dos CSVs. |
| `/tmp/smoke_importer.rb` | Smoke E2E: 1 paciente + 1 anamnese + 4 respostas. |
| `/tmp/validate_loaders.rb` | Sanity-check: classes carregam, importer instancia. |

## 9. Criação dos 8 Dentistas (Pré-condição da Importação de Agenda)

Antes da primeira import de agenda, foram criados 8 usuários do tipo agente (role `agent` em `AccountUser`) com nomes vindos do cliente, e-mails aleatórios e senhas aleatórias. O importer de agenda usa esses nomes pra resolver `DentistName` em `user_id`:

- Aline Pereira
- Claudia Raquel Sevegnani
- (+ 6 outros)

Match feito em `find_user`:

```ruby
norm = normalize(name)  # downcase + strip
@account.users.find { |u| normalize(u.name) == norm }
```

Cache em memória pra evitar N queries.

## 10. Análise de Arquitetura Limpa

| Critério | Status |
|---|---|
| Lógica de negócio isolada no plugin | ✅ Toda em `plugins/migration/app/services/` |
| Modelos do core não estendidos com lógica de migração | ✅ `Patient`, `Anamnesis`, `AgendaEvent`, `User` consumidos via API pública (`create!`, `update!`) — zero monkey-patch |
| Migrations de banco isoladas | ✅ `plugins/migration/db/migrate/` registrado via `Engine#initializer 'migration.db'` |
| Tabelas próprias com prefixo claro | ✅ `migration_runs` é o único schema novo |
| Frontend isolado | ✅ `plugins/migration/frontend/` (Vue 3 + fetch nativo, sem store global Vuex/Pinia) |
| Sem dependência de inicialização de outros plugins | ✅ Importer aceita `MigrationRun` por DI; não toca em estado global |
| Comportamento backwards-compatible | ✅ `ProcessCsvJob` aceita assinatura antiga (String) e nova (Hash) |
| Erros nunca são silenciados | ✅ Tudo vai pra `errors_log` jsonb (limitado a 200 entradas pra não estourar memória) |

**Pontos de atrito conhecidos** (registrados pra revisão futura):

1. **SuperAdmin controller no core** (ver Seção 6). Acoplamento ao Administrate.
2. **Reload de classes em dev** — Sidekiq em modo desenvolvimento recarrega a cada job, então edições no importer pegam sem restart. Em produção, restart obrigatório.
3. **Limite de 25MB por arquivo** — válido pros CSVs atuais da Clinicorp (~10k linhas). Se ficar pequeno, considerar upload via S3 + processamento por chunks.
4. **Bugs corrigidos no plugin de pacientes (per_page, birthdate)** — não são do módulo Migração em si, mas foram descobertos via teste do importer. Doc-trail aqui pra contexto.

## 11. Decisões Notáveis (Por Quê)

- **Índice clinicorp_id apenas em memória, não persistido em coluna.** O `Patient.csv` SEMPRE vem junto com os anamneses, então não precisa sobreviver entre runs. Evita migration nova e mantém o schema do core intocado.
- **Chave de mapeamento de pergunta usa `include?` (substring).** Os textos da Clinicorp variam em pontuação, capitalização e espaços; substring case-insensitive é mais resistente que match exato. Custo: chance pequena de falso-positivo se uma pergunta nova contiver acidentalmente uma substring mapeada — mitigado por revisão manual antes de adicionar entradas no `ANAMNESIS_QUESTION_MAP`.
- **Pergunta não mapeada vai pra `additional_notes`, não falha.** Princípio: importar dado clínico imperfeito é melhor que importar dado clínico nenhum. O dentista revisa.
- **Detecção de colisão de truncamento bloqueia em vez de chutar.** Risco de prontuário cruzado é inaceitável — preferimos perder uma anamnese e logar que mover dado clínico pro paciente errado.
- **Service de agenda só é criado quando `Procedures` está preenchido.** Evita "Odonto" genérico falso. UI mostra placeholder "Selecione o tratamento" quando vazio.
- **Categoria como `select` em vez de texto livre.** Coleta valores únicos do CSV no primeiro passe, cria `AgendaCustomAttribute` com `field_type='select'`. Em re-imports, faz union (preserva opções já existentes).
- **Score de campos pra decidir merge.** Linha do CSV vs paciente existente — quem tem mais campos populados ganha. Ao atualizar, **só preenche campos vazios** do existing. Nunca destrói dado já populado.

## 12. Validação Realizada

- **Truncamento Excel:** 30/30 pares (id exato → forma `X,XXXXXE+15`) batendo com os CSVs reais do cliente. Validado via `/tmp/validate_trunc.rb`.
- **Smoke E2E:** 1 paciente + 1 anamnese + 4 respostas (incluindo 1 pergunta não mapeada). Resultado: paciente criado, anamnese vinculada via truncamento, `chief_complaint` / `allergies` / `pregnancy` populados nos campos certos, pergunta órfã caiu em `additional_notes`. 0 erros. Validado via `/tmp/smoke_importer.rb`.
- **Import real (1ª rodada):** 2.433 pacientes importados, 27 anamneses linkadas com sucesso (Patient.csv + os 2 CSVs de anamnese da Clinicorp do cliente). 0 colisões de truncamento.
- **Pacientes com flags clínicas detectadas:**
  - `pregnancy.is_pregnant=true`: Nadiete Gaedtke
  - `allergies.length > 0`: Bianca Caroline Aguiar, Joelcio Langa, Leandro Dalprá, Nadiete Gaedtke

## 13. Próximos Passos (não nesta entrega)

- Importador Anamnesis para template **EXPERTISE** (estética facial — outras perguntas, mesmo modelo).
- Importador Financeiro (transações + parcelas Clinicorp → `Transaction`/`Installment`).
- Mover `SuperAdmin::MigrationsController` para concern dentro do plugin (resolver acoplamento Administrate).
- Histórico de runs no UI com filtro por conta + drill-down nos `errors_log` formatados.
- Botão "re-rodar run" no UI (re-enfileira o job com os mesmos CSVs persistidos em ActiveStorage).
