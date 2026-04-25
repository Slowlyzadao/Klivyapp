# 🏗️ KlivyApp / BeClinic — Arquitetura de Sistema (Modular Monolith)

> Este documento é a fonte da verdade sobre como a aplicação SaaS BeClinic foi acoplada ao Chatwoot.

---

## 1. Visão Geral

A arquitetura do BeClinic utiliza o padrão **Modular Monolith via Rails Engines**. O projeto iniciou com modificações diretas no core do Chatwoot, mas evoluiu (de forma limpa e estruturada) para garantir isolamento físico, mitigação total de conflitos de banco de dados, e velocidade de compilação.

Todo código do BeClinic vive estritamente na pasta `plugins/`, e toda mutação do núcleo original (como injeção de perfis na classe `Account`) ocorre em tempo real, em memória dinâmica, preservando os arquivos do Chatwoot intocados.

## 2. Estrutura de Módulos (Plugins)

Cada Módulo de negócio é um ecossistema independente (com sua própria API, Rotas, Models, e Store Angular/Vue). O Vite foi configurado via Alias (`@plugins/...`) para compilar esses injetáveis no pipeline original do Chatwoot.

### 📋 Módulo 1: SYSTEM CORE (`plugins/beclinic_core`)
Responsável pelas regras basais, Perfis Satélites, Configurações, e RBAC (Role-Based Access Control).
- **Frontend**: Configurações de Equipe, Vite Aliases
- **Banco de Dados (Satélite)**: `beclinic_team_profiles`, `beclinic_account_profiles`, `beclinic_user_profiles`
- **Técnica de Isolamento**: O engine deste módulo abriga o callback `Account.class_eval`, `User.class_eval`, e `Team.class_eval`, embutindo a lógica de perfis customizados via proxy pattern (`delegate`). Isso mantém o banco da Chatwoot vazio.

### 📋 Módulo 2: AGENDA (`plugins/agenda`)
Agendamento inteligente. Adotou arquitetura "Mobile-First" 100% responsiva (CSS Grid/Flexbox) desacoplada do core do Chatwoot. 
- **Frontend**: `frontend/routes/AgendaDashboard.vue`, CSS responsivo centralizado.
- **Backend API**: Endpoints isolados.
- **Modelos Isolados**: Gerencia Blocks, Appointments. 

### 📋 Módulo 3: PACIENTES (`plugins/patients`)
Prontuário Médico Eletrônico robusto.
- **Composição**: Dezenas de endpoints isolados (Anamnesis, Tratamento, Consentimentos).
- **Associações em Memória**: `plugins/patients/lib/patients/engine.rb` contém `Account.class_eval` adicionando os `has_many` de prontuários, sem relar no `app/models/account.rb` físico.

### 📋 Módulo 4: FINANCEIRO (`plugins/financial`)
Gestor DRE e PDV clinicamente avançado.
- **Relatórios Nativos**: Gerador de Fluxo de Caixa Diário + Dashboards 100% Prawn PDF (zero dependências externas ou conflitos ARM M1).
- **Composição**: Associações financeiras no `Account.class_eval` injetados nativamente via seu respectivo Engine.

## 3. Isolamento de Banco de Dados (Database Hygiene)

O Chatwoot possui tabelas nucleares: `accounts`, `users`, `teams`.
**NENHUMA** coluna proprietária do BeClinic (ex: `monthly_goal`, `beclinic_role`, `permissions`) existe no meio dessas tabelas do Chatwoot.

Se a base de dados precisar de propriedades adicionais na Conta ou Equipe, criamos via `has_one :beclinic_profile` associando a um model Satélite (ex: `BeclinicCore::AccountProfile`).
O método `delegate :monthly_goal, to: :beclinic_profile` recria as propriedades para os Controladores pensarem que a Conta do Chatwoot é a proprietária da informação.

## 4. Como Funcionam as "Injeções Mágicas"?

Quando o servidor Rails boota, ele lê os plugins carregados no `Gemfile` e aciona blocos de memória chamados `config.to_prepare do`. 

**Para Associações Modelos**:
A injeção ocorre silenciosamente e em tempo de runtime:

```ruby
Account.class_eval do
  has_many :patients, class_name: 'Patient', dependent: :destroy
  # ...outros has_many modulares
end
```

**Para Frontend**:
Nó compilamos o Vue.js usando importações diretas do Chatwoot Main Dashboard:
`import agendaRoutes from '@plugins/agenda/frontend/routes/agenda.routes'`
O arquivo `vite.config.ts` é encarregado de desviar essas rotas apontadas com Alias para as subpastas físicas isoladas.

---
> Estado de Auditoria: V2 (Fully Decoupled Modular Monolith)
