#!/bin/bash

# Criar Estrutura de Pastas
mkdir -p docs/01-product/modules
mkdir -p docs/02-architecture
mkdir -p docs/03-engineering
mkdir -p docs/04-decisions
mkdir -p docs/05-archive

# 1. Obsoletos (Remover)
rm -f docs/notes/changelog_Qwen.md
rm -f docs/notes/KNOWLEDGE_ITEMS.md
rm -f docs/plans/graficos_plano_de_acao.md
rm -f docs/plans/pacientes_plan_2.md

# 2. Produto (Realocar e Fundir)
mv docs/PRD_FINAL.md docs/01-product/PRD.md

# Agenda
cat docs/plans/AGENDA_PLAN.md docs/plans/AGENDA_ONLINE_PLAN.md > docs/01-product/modules/agenda.md
rm -f docs/plans/AGENDA_PLAN.md docs/plans/AGENDA_ONLINE_PLAN.md

# Pacientes
cat docs/plans/pacientes_plan.md > docs/01-product/modules/pacientes.md
rm -f docs/plans/pacientes_plan.md

# Financeiro
cat docs/plans/financeiro_plan.md docs/plans/spec.financeiro.md docs/notes/financeiro_how_to_use.md docs/plans/financeiro_graphics.md > docs/01-product/modules/financeiro.md
rm -f docs/plans/financeiro_plan.md docs/plans/spec.financeiro.md docs/notes/financeiro_how_to_use.md docs/plans/financeiro_graphics.md

# Configurações (RBAC)
cat docs/plans/RBAC_Plan.md > docs/01-product/modules/configuracoes.md
rm -f docs/plans/RBAC_Plan.md

# 3. Arquitetura
mv docs/ANALISE_ARQUITETURAL.md docs/02-architecture/system-architecture.md
cat docs/plans/FINANCIAL_ARCHITECTURE.md docs/plans/FINANCIAL_DASHBOARD_ARCHITECTURE.md > docs/02-architecture/financial-architecture.md
rm -f docs/plans/FINANCIAL_ARCHITECTURE.md docs/plans/FINANCIAL_DASHBOARD_ARCHITECTURE.md

# 4. Engenharia
mv docs/DOCKER_COMMANDS.md docs/03-engineering/docker.md
cat docs/STYLE.md docs/notes/AGENTS.md > docs/03-engineering/development.md
rm -f docs/STYLE.md docs/notes/AGENTS.md

# 5. Backup Legado
mv docs/MAPA_MODULOS.md docs/02-architecture/system-architecture.md

rmdir docs/notes docs/plans --ignore-fail-on-non-empty

echo "Auditoria Finalizada! Docs limpos e reorganizados."
