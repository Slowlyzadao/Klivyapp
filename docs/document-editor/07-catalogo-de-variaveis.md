# 07 — Catálogo de Variáveis (MVP)

> Esta é a fonte da verdade do MVP. Toda variável aqui listada deve ser implementada no `DocumentTemplates::Catalog` (backend) e exposta no endpoint `GET /api/v1/accounts/:id/document_templates/variables`.

## 7.1 Convenções

- **Chave (`key`)**: `categoria.atributo`, snake_case, estável (nunca mudar depois de release).
- **Label**: portuguÊs claro, sem siglas internas.
- **Categoria**: agrupador no UI (Paciente, Clínica, Profissional, Data).
- **Formatter**: nome do helper Ruby (`:cpf`, `:date_long`, etc.) — opcional.
- **Exemplo**: valor de mostra no UI pra educar usuário.
- **Fallback**: o que mostrar no PDF se valor for null. Padrão: `_______`.

## 7.2 Categoria: Paciente

| Chave | Label | Formatter | Exemplo | Fonte (model) |
|---|---|---|---|---|
| `patient.full_name` | Nome completo | — | Maria Silva Santos | `patient.full_name` |
| `patient.first_name` | Primeiro nome | — | Maria | derivado |
| `patient.last_name` | Sobrenome | — | Silva Santos | derivado |
| `patient.cpf` | CPF | `:cpf` | 123.456.789-00 | `patient.cpf` |
| `patient.rg` | RG | — | 12.345.678-9 | `patient.rg` |
| `patient.birth_date` | Data de nascimento | `:date_short` | 15/03/1985 | `patient.birth_date` |
| `patient.birth_date_long` | Data de nasc. por extenso | `:date_long` | 15 de março de 1985 | derivado |
| `patient.age` | Idade | `:age` | 39 anos | calculado |
| `patient.gender` | Gênero | — | Feminino | `patient.gender` |
| `patient.phone` | Telefone | `:phone` | (11) 98765-4321 | `patient.phone` |
| `patient.email` | E-mail | — | maria@email.com | `patient.email` |
| `patient.address_full` | Endereço completo | — | Rua X, 100, ap 5, Vila Y, São Paulo-SP, 01000-000 | composto |
| `patient.address_street` | Logradouro | — | Rua das Flores, 100 | `patient.address_street` + `address_number` |
| `patient.address_complement` | Complemento | — | Ap 5, Bl A | `patient.address_complement` |
| `patient.address_neighborhood` | Bairro | — | Vila Mariana | `patient.address_neighborhood` |
| `patient.address_city` | Cidade | — | São Paulo | `patient.address_city` |
| `patient.address_state` | Estado (UF) | — | SP | `patient.address_state` |
| `patient.address_zip` | CEP | `:cep` | 01000-000 | `patient.address_zip` |
| `patient.responsible_name` | Nome do responsável (menor) | — | José Silva | `patient.responsible_name` |
| `patient.responsible_cpf` | CPF do responsável | `:cpf` | 987.654.321-00 | `patient.responsible_cpf` |
| `patient.medical_record_id` | Nº prontuário | — | 1234 | `patient.id` formatado |

**Verificar antes de implementar**: os campos `responsible_name`/`responsible_cpf` existem no modelo `Patient`? Se não, são *recomendados* mas dependem do schema atual — listar no `10-pontos-de-atencao.md` e adicionar migration se necessário.

## 7.3 Categoria: Clínica

| Chave | Label | Formatter | Exemplo | Fonte |
|---|---|---|---|---|
| `clinic.name` | Nome da clínica | — | Clínica Bem Estar | `account.name` |
| `clinic.fantasy_name` | Nome fantasia | — | Bem Estar Estética | `account.custom_attributes['fantasy_name']` |
| `clinic.cnpj` | CNPJ | `:cnpj` | 12.345.678/0001-90 | `account.custom_attributes['cnpj']` |
| `clinic.address_full` | Endereço completo | — | Av. Paulista, 1000, Sala 100, Bela Vista, São Paulo-SP, 01310-100 | composto |
| `clinic.address_street` | Logradouro | — | Av. Paulista, 1000 | `account.address_street` |
| `clinic.address_city` | Cidade | — | São Paulo | `account.address_city` |
| `clinic.address_state` | Estado (UF) | — | SP | `account.address_state` |
| `clinic.address_zip` | CEP | `:cep` | 01310-100 | `account.address_zip` |
| `clinic.phone` | Telefone | `:phone` | (11) 3000-3000 | `account.phone` |
| `clinic.email` | E-mail | — | contato@bemestar.com | `account.email` |
| `clinic.website` | Site | — | bemestar.com.br | `account.custom_attributes['website']` |
| `clinic.logo_url` | Logo (imagem) | `:image_tag` | (renderiza `<img>`) | `account.logo.url` |

**Notas:**
- Vários desses campos provavelmente vivem em `account.custom_attributes` (JSONB) hoje. **Mapear durante implementação** — pode exigir migration pra colunas dedicadas.
- `logo_url` formatter `:image_tag` é especial: o renderer Ruby substitui não por texto, mas por `<img src="...">` no HTML final.

## 7.4 Categoria: Profissional

O "Profissional" é **o User logado que está gerando o documento** — não um dado fixo do paciente.

| Chave | Label | Formatter | Exemplo | Fonte |
|---|---|---|---|---|
| `professional.name` | Nome | — | Dr. Carlos Andrade | `user.name` |
| `professional.email` | E-mail | — | carlos@clinica.com | `user.email` |
| `professional.council_acronym` | Conselho | — | CRM | `user.council_acronym` ou custom |
| `professional.council_number` | Nº do conselho | — | 123456 | `user.council_number` |
| `professional.council_state` | UF do conselho | — | SP | `user.council_state` |
| `professional.council_full` | Conselho completo | — | CRM/SP 123456 | composto |
| `professional.specialty` | Especialidade | — | Dermatologia | `user.specialty` |
| `professional.signature_image_url` | Assinatura escaneada | `:image_tag` | `<img>` | `user.signature.url` |

**Notas:**
- Vários desses campos provavelmente não existem no User atual. **Verificar e estender** o modelo durante implementação.
- `signature_image_url` permite que o profissional cadastre uma imagem de assinatura escaneada que aparece no documento gerado — comum em receitas/atestados. Não confundir com assinatura eletrônica (Clicksign).

## 7.5 Categoria: Data e Hora

Variáveis automáticas — calculadas no momento da geração.

| Chave | Label | Formatter | Exemplo |
|---|---|---|---|
| `date.today` | Data de hoje | `:date_short` | 26/05/2026 |
| `date.today_long` | Data por extenso | `:date_long` | 26 de maio de 2026 |
| `date.day` | Dia | — | 26 |
| `date.day_padded` | Dia (2 dígitos) | — | 26 |
| `date.month` | Mês (nome) | — | maio |
| `date.month_number` | Mês (número) | — | 5 |
| `date.year` | Ano | — | 2026 |
| `date.day_of_week` | Dia da semana | — | terça-feira |
| `date.city_today` | "Cidade, data por extenso" | — | São Paulo, 26 de maio de 2026 |
| `date.time` | Hora atual | — | 14:30 |
| `date.datetime` | Data + hora | — | 26/05/2026 14:30 |

**Locale**: todos em `pt-BR`. Definir no `I18n.locale`.

## 7.6 Variáveis fora do MVP (Fase 2)

Catálogo pra referência futura — **não implementar agora**:

### Tratamento/Procedimento (Fase 2)
- `treatment.name`, `treatment.description`, `treatment.value`, `treatment.installments`, `treatment.start_date`, `treatment.session_count`, `treatment.next_session`

### Financeiro (Fase 2)
- `financial.total_value`, `financial.discount`, `financial.payment_method`, `financial.installment_count`, `financial.first_due_date`, `financial.interest_rate`

### Agendamento (Fase 2)
- `appointment.date`, `appointment.time`, `appointment.duration`, `appointment.professional_name`

### Customizadas pela clínica (Fase 3)
- A clínica define no Settings: `custom.{slug}` com valor estático ou puxado de qualquer campo.

## 7.7 Tratamento de valores nulos

Quando o valor resolve pra `nil` ou string vazia:

1. Se o **template define** `fallback`, usa esse valor (ex: `"___________"`, `"a definir"`, `"(em branco)"`).
2. Se não define, padrão global: `"_______"` (7 underscores).
3. **Variáveis obrigatórias** (futuro): marcar `required: true` no catálogo. Se nulo, **bloqueia geração** com erro claro.

## 7.8 Formatadores — referência

| Nome | Entrada | Saída | Onde |
|---|---|---|---|
| `:cpf` | "12345678900" | "123.456.789-00" | `Resolver#format_cpf` |
| `:cnpj` | "12345678000190" | "12.345.678/0001-90" | `Resolver#format_cnpj` |
| `:phone` | "11987654321" | "(11) 98765-4321" | `Resolver#format_phone` |
| `:cep` | "01310100" | "01310-100" | `Resolver#format_cep` |
| `:date_short` | Date | "26/05/2026" | I18n `:default` |
| `:date_long` | Date | "26 de maio de 2026" | I18n `:long` |
| `:age` | Date (nascimento) | "39 anos" | `Resolver#calculate_age` |
| `:currency` | 1234.5 | "R$ 1.234,50" | `ActiveSupport::NumberHelper` |
| `:uppercase` | "Maria" | "MARIA" | `String#upcase` |
| `:image_tag` | URL | `<img src="...">` | renderer especial |

## 7.9 Como o frontend organiza isso no menu de inserção

Endpoint `/api/v1/accounts/:id/document_templates/variables` retorna lista plana. Frontend agrupa por `category` e mostra:

```
┌─────────────────────────────────┐
│ [🔍 Buscar variável...]         │
├─────────────────────────────────┤
│ 👤 PACIENTE                     │
│   ▢ Nome completo               │
│   ▢ CPF                         │
│   ▢ RG                          │
│   ▢ Data de nascimento          │
│   ▢ Idade                       │
│   ▢ Endereço completo           │
│   ▼ Mostrar mais (15)           │
├─────────────────────────────────┤
│ 🏥 CLÍNICA                      │
│   ▢ Nome da clínica             │
│   ▢ CNPJ                        │
│   ▼ Mostrar mais (10)           │
├─────────────────────────────────┤
│ 👨‍⚕️ PROFISSIONAL                 │
│ 📅 DATA                          │
└─────────────────────────────────┘
```

**Categorias colapsáveis**, expandidas por padrão no MVP. Busca filtra em todas.

## 7.10 Total de variáveis no MVP

| Categoria | Quantas |
|---|---|
| Paciente | ~20 |
| Clínica | ~12 |
| Profissional | ~8 |
| Data/Hora | ~11 |
| **TOTAL** | **~51** |

51 variáveis é o suficiente pra cobrir 95% dos casos clínicos comuns. Fase 2 expande pra tratamento/financeiro/agendamento.
