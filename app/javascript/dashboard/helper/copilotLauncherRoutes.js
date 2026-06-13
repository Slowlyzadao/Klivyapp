/**
 * Marca recursivamente um conjunto de rotas com `meta.hideCopilotLauncher = true`.
 *
 * Usado pra esconder o FAB flutuante do Captain (copiloto nativo) nos módulos
 * Klivy — Agenda, Pacientes, Financeiro, Chat Interno, BEA (ai_agent), Ajuda e
 * Papéis (custom_roles). O Captain é uma IA de ATENDIMENTO (lê a conversa e
 * sugere resposta); nesses módulos clínicos ele não tem contexto nem atuação,
 * então o botão flutuante é só ruído + risco de sobreposição com a UI própria
 * de cada módulo (ex.: cobria o botão Enviar do Chat Interno).
 *
 * Marcamos no PONTO DE REGISTRO das rotas (dashboard.routes.js / settings.routes.js)
 * em vez de manter uma lista de nomes de rota no componente: módulo novo entra
 * só adicionando seu spread aqui e já nasce sem o FAB.
 *
 * `route.meta` é mesclado pai→filho no Vue Router, mas marcamos RECURSIVAMENTE
 * pra cobrir também rotas-irmãs sem pai comum (ex.: Pacientes tem 2 rotas
 * top-level) e qualquer override de meta em filhos.
 */
export const hideCopilotLauncherOn = routes =>
  routes.map(route => ({
    ...route,
    meta: { ...(route.meta || {}), hideCopilotLauncher: true },
    ...(route.children
      ? { children: hideCopilotLauncherOn(route.children) }
      : {}),
  }));
