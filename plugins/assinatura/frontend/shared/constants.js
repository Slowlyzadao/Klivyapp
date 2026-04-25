export const PLAN_FEATURES = [
  { key: 'agenda',            label: 'Módulo Agenda',         icon: 'calendar' },
  { key: 'patients',          label: 'Módulo Pacientes',      icon: 'heart' },
  { key: 'chatbot',           label: 'Chatbot / Automações',  icon: 'robot' },
  { key: 'reports',           label: 'Relatórios Avançados',  icon: 'chart' },
  { key: 'api',               label: 'Acesso à API',          icon: 'code' },
  { key: 'integrations',      label: 'Integrações Premium',   icon: 'plug' },
  { key: 'help_center',       label: 'Central de Ajuda',      icon: 'book' },
  { key: 'priority_support',  label: 'Suporte Prioritário',   icon: 'headset' },
  { key: 'white_label',       label: 'Sem Marca Klivy',       icon: 'shield' },
  { key: 'custom_domain',     label: 'Domínio Personalizado', icon: 'globe' },
  { key: 'unlimited_agents',  label: 'Agentes Ilimitados',    icon: 'user-add' },
  { key: 'unlimited_inboxes', label: 'Inboxes Ilimitadas',    icon: 'checkbox' },
];

export const PLAN_LIMITS = [
  { key: 'agents',            label: 'Agentes',           placeholder: 'Ilimitado' },
  { key: 'inboxes',           label: 'Inboxes',            placeholder: 'Ilimitado' },
  { key: 'captain_responses', label: 'Respostas IA / mês', placeholder: 'Ilimitado' },
  { key: 'captain_documents', label: 'Documentos IA',      placeholder: 'Ilimitado' },
  { key: 'emails',            label: 'E-mails / mês',      placeholder: 'Ilimitado' },
];

export const COUPON_KINDS = [
  { value: 'trial',        label: 'Período Grátis (Trial)' },
  { value: 'percent',      label: 'Desconto Percentual' },
  { value: 'fixed_value',  label: 'Desconto em R$ Fixo' },
  { value: 'free_forever', label: 'Grátis Para Sempre' },
];

export const PLAN_COLORS = [
  '#5B5BD6', // Iris
  '#12A594', // Teal
  '#E54666', // Ruby
  '#F76B15', // Orange
  '#2B9EB3', // Cyan
  '#8B5CF6', // Violet
  '#059669', // Emerald
  '#DC2626', // Red
];

export function getCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? '';
}

export function formatPrice(value) {
  if (value == null) return '—';
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value);
}

export function getCheckoutUrl(plan) {
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  return `${origin}/checkout.html?plan=${plan.slug || plan.id}`;
}
