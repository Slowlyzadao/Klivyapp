<script setup>
import { ref, computed, onMounted, reactive, watch, nextTick } from 'vue';
import { useStore } from 'vuex';

const store = useStore();

const records = computed(() => store.getters['aiAgentInternalNotificationTemplates/getRecords']);
const catalog = computed(() => store.getters['aiAgentInternalNotificationTemplates/getCatalog']);
const uiFlags = computed(() => store.getters['aiAgentInternalNotificationTemplates/getUIFlags']);

const showModal = ref(false);
const editingId = ref(null);
const bodyTextareaRef = ref(null);

// Mapeia color string → cores hex (Tailwind JIT não pega classe dinâmica).
const COLOR_MAP = {
  sky:    { bg: '#e0f2fe', fg: '#0284c7' },
  amber:  { bg: '#fef3c7', fg: '#d97706' },
  rose:   { bg: '#ffe4e6', fg: '#e11d48' },
  red:    { bg: '#fee2e2', fg: '#dc2626' },
  orange: { bg: '#ffedd5', fg: '#ea580c' },
  slate:  { bg: '#f1f5f9', fg: '#475569' },
  emerald:{ bg: '#d1fae5', fg: '#059669' },
  cyan:   { bg: '#cffafe', fg: '#0891b2' },
  violet: { bg: '#ede9fe', fg: '#7c3aed' },
};

const colorFor = name => COLOR_MAP[name] || COLOR_MAP.slate;

const detectorBadge = status => {
  if (status === 'active' || status === ':active') return { text: 'Ativo', color: '#059669', bg: '#d1fae5' };
  return { text: 'Em breve', color: '#b45309', bg: '#fef3c7' };
};

const TARGET_TYPE_OPTIONS = [
  { value: 'room',     label: 'Sala do Chat Interno' },
  { value: 'user',     label: 'DM com pessoa específica' },
  { value: 'disabled', label: 'Desativado (não notifica)' },
];

const emptyForm = () => ({
  event_key: '',
  name: '',
  body: '',
  target_type: 'room',
  target_id: null,
  enabled: true,
});

const form = reactive(emptyForm());

const editingTemplate = computed(() =>
  records.value.find(r => r.id === editingId.value)
);

const availableVars = computed(() => editingTemplate.value?.available_vars || []);

const targetOptions = computed(() => {
  if (form.target_type === 'room') {
    return catalog.value.rooms.map(r => ({
      value: r.id,
      label: r.system_role ? `${r.name} (sistêmica)` : r.name,
    }));
  }
  if (form.target_type === 'user') {
    return catalog.value.users.map(u => ({ value: u.id, label: u.name }));
  }
  return [];
});

const detectorActive = computed(() => {
  const s = editingTemplate.value?.detector_status;
  return s === 'active' || s === ':active';
});

const openEdit = template => {
  Object.assign(form, {
    event_key: template.event_key,
    name: template.name,
    body: template.body,
    target_type: template.target_type,
    target_id: template.target_id,
    enabled: template.enabled,
  });
  editingId.value = template.id;
  showModal.value = true;
};

const closeModal = () => {
  showModal.value = false;
  editingId.value = null;
};

const save = async () => {
  const payload = { ...form };
  // se desactivated, target_id deve ser null
  if (payload.target_type === 'disabled') payload.target_id = null;

  try {
    await store.dispatch('aiAgentInternalNotificationTemplates/update', { id: editingId.value, ...payload });
    closeModal();
  } catch (e) {
    /* throwErrorMessage já dispara toast */
  }
};

const toggleEnabled = async template => {
  await store.dispatch('aiAgentInternalNotificationTemplates/update', {
    id: template.id,
    enabled: !template.enabled,
  });
};

const resetTemplate = async template => {
  if (!window.confirm(`Restaurar "${template.event_label}" pro template padrão? As edições atuais serão perdidas.`)) return;
  await store.dispatch('aiAgentInternalNotificationTemplates/reset', template.id);
};

const insertVar = varName => {
  const ta = bodyTextareaRef.value;
  if (!ta) return;
  const start = ta.selectionStart;
  const end = ta.selectionEnd;
  const placeholder = `%{${varName}}`;
  form.body = form.body.slice(0, start) + placeholder + form.body.slice(end);
  nextTick(() => {
    const pos = start + placeholder.length;
    ta.focus();
    ta.setSelectionRange(pos, pos);
  });
};

// Preview do body com variáveis simuladas (pra clínica ver como vai ficar)
const FAKE_VARS = {
  patient_name: 'Maria Silva',
  patient_phone: '+5511999998888',
  patient_status: '(acabei de criar a ficha)',
  service_name: 'Avaliação ortodôntica',
  dentist_name: 'Dr. João',
  appointment_starts_at: 'segunda, 14:30',
  last_visit_line: '📌 Última visita: 15/02/2026',
  reason: 'Slot ocupou entre confirmação e save',
  conversation_link: 'https://app.klivy.com/conversations/123',
  summary: 'Pediu reembolso da consulta de 03/05',
  debt_amount: 'R$ 450,00',
  debt_summary: 'Sessão 02 e 03 de canal vencidas há 30 dias',
  trigger_terms: 'sangrando muito, não para',
  failure_count: '4',
  topics: 'preço de canal, plano Amil, horário sábado',
};

const renderedPreview = computed(() => {
  return form.body.replace(/%\{(\w+)\}/g, (_m, k) => FAKE_VARS[k] || `[${k}?]`);
});

const cardCount = computed(() => records.value.length);
const activeCount = computed(() => records.value.filter(r => r.enabled && r.target_type !== 'disabled').length);

watch(showModal, val => {
  document.body.style.overflow = val ? 'hidden' : '';
});

onMounted(() => {
  store.dispatch('aiAgentInternalNotificationTemplates/fetch');
  store.dispatch('aiAgentInternalNotificationTemplates/fetchCatalog');
});
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background overflow-hidden">
    <!-- Header -->
    <header class="flex-shrink-0 px-8 py-6 border-b border-n-weak bg-n-solid-1">
      <div class="flex items-start justify-between gap-6">
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-3 flex-wrap">
            <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">Templates de notificação interna</h1>
            <span
              v-if="cardCount > 0"
              class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500" />
              {{ activeCount }} {{ activeCount === 1 ? 'ativo' : 'ativos' }}
              <span class="text-n-slate-9">·</span>
              {{ cardCount }} no total
            </span>
          </div>
          <p class="text-sm text-n-slate-11 mt-1.5 max-w-3xl leading-relaxed">
            Configure quais avisos a Beatriz manda no Chat Interno e pra qual sala ou pessoa cada um vai. As mensagens são pré-definidas (zero token) — você edita o texto, escolhe o destino e ativa.
          </p>
        </div>
      </div>
    </header>

    <main class="flex-1 overflow-y-auto">
      <div class="px-8 py-8 w-full">
        <!-- Loading -->
        <div v-if="uiFlags.isFetching && records.length === 0" class="flex items-center justify-center py-20">
          <div class="flex items-center gap-3 text-sm text-n-slate-10">
            <svg class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round"/></svg>
            Carregando templates…
          </div>
        </div>

        <!-- Cards -->
        <div v-else class="grid gap-4 grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3">
          <article
            v-for="t in records"
            :key="t.id"
            class="group relative bg-n-solid-1 border border-n-weak rounded-2xl p-5 hover:border-n-strong hover:shadow-md transition-all flex flex-col"
            :class="{ 'opacity-70': !t.enabled || t.target_type === 'disabled' }"
          >
            <!-- Top: ícone + título + badges -->
            <div class="flex items-start justify-between gap-3 mb-3">
              <div class="flex items-start gap-3 min-w-0 flex-1">
                <div
                  class="shrink-0 flex items-center justify-center w-10 h-10 rounded-xl"
                  :style="{ backgroundColor: colorFor(t.color).bg }"
                >
                  <svg class="w-5 h-5" :style="{ color: colorFor(t.color).fg }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
                  </svg>
                </div>
                <div class="min-w-0 flex-1">
                  <h3 class="text-base font-semibold text-n-slate-12 truncate leading-tight">{{ t.event_label }}</h3>
                  <p class="text-xs text-n-slate-10 mt-0.5 line-clamp-2 leading-relaxed">{{ t.event_description }}</p>
                </div>
              </div>
              <span
                class="shrink-0 inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium rounded-md"
                :class="t.enabled && t.target_type !== 'disabled' ? 'bg-emerald-100 text-emerald-700' : 'bg-n-alpha-2 text-n-slate-10'"
              >
                <span class="w-1.5 h-1.5 rounded-full" :class="t.enabled && t.target_type !== 'disabled' ? 'bg-emerald-500' : 'bg-n-slate-9'" />
                {{ t.enabled && t.target_type !== 'disabled' ? 'Ativo' : 'Desativado' }}
              </span>
            </div>

            <!-- Pills -->
            <div class="flex flex-wrap items-center gap-2 mb-4">
              <span
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                {{ t.target_label }}
              </span>
              <span
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md"
                :style="{ color: detectorBadge(t.detector_status).color, backgroundColor: detectorBadge(t.detector_status).bg }"
              >
                {{ detectorBadge(t.detector_status).text }}
              </span>
            </div>

            <!-- Body preview -->
            <p class="text-sm text-n-slate-11 leading-relaxed line-clamp-3 mb-4 min-h-[3.9em] flex-1 whitespace-pre-line">
              {{ t.body }}
            </p>

            <!-- Actions -->
            <div class="flex items-center gap-1 -mx-1.5 -mb-1.5 pt-3 border-t border-n-weak mt-auto">
              <button
                type="button"
                class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                @click="toggleEnabled(t)"
              >
                <svg v-if="t.enabled" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>
                <svg v-else class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="6 3 20 12 6 21 6 3"/></svg>
                {{ t.enabled ? 'Pausar' : 'Ativar' }}
              </button>
              <button
                type="button"
                class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                @click="openEdit(t)"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/></svg>
                Editar
              </button>
              <button
                type="button"
                class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                title="Restaurar pro padrão"
                @click="resetTemplate(t)"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/></svg>
                Restaurar
              </button>
            </div>
          </article>
        </div>
      </div>
    </main>

    <!-- Modal de edit -->
    <Teleport to="body">
      <Transition name="modal">
        <div
          v-if="showModal"
          class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
          @click.self="closeModal"
        >
          <div
            class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-5xl max-h-[92vh] flex flex-col overflow-hidden"
            @click.stop
          >
            <header class="flex-shrink-0 px-7 py-5 border-b border-n-weak flex items-start justify-between gap-4">
              <div class="min-w-0">
                <h2 class="text-lg font-semibold text-n-slate-12 leading-tight">
                  Editar template
                </h2>
                <p class="text-xs text-n-slate-10 mt-1">
                  {{ editingTemplate?.event_label }}
                  <span v-if="!detectorActive" class="ml-2 px-1.5 py-0.5 rounded text-[10px] font-medium" style="color: #b45309; background: #fef3c7;">
                    detector ainda não ativo — disparo automático em breve
                  </span>
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
                @click="closeModal"
              >
                <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>
              </button>
            </header>

            <!-- Body: 2 cols (form esquerda, vars/preview direita) -->
            <form class="flex-1 overflow-y-auto px-7 py-6" @submit.prevent="save">
              <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <!-- Coluna esquerda (2/3) -->
                <div class="lg:col-span-2 space-y-5">
                  <!-- Nome -->
                  <div>
                    <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">Nome (uso interno)</label>
                    <input
                      v-model="form.name"
                      type="text"
                      required
                      maxlength="120"
                      class="w-full h-11 px-3.5 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                    >
                  </div>

                  <!-- Destino -->
                  <div>
                    <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">Onde enviar</label>
                    <div class="grid grid-cols-3 gap-2 mb-2">
                      <button
                        v-for="opt in TARGET_TYPE_OPTIONS"
                        :key="opt.value"
                        type="button"
                        class="px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-all"
                        :class="form.target_type === opt.value
                          ? 'border-woot-500 bg-woot-50 text-n-slate-12'
                          : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1 text-n-slate-11'"
                        @click="form.target_type = opt.value; form.target_id = null"
                      >
                        {{ opt.label }}
                      </button>
                    </div>
                    <select
                      v-if="form.target_type !== 'disabled'"
                      v-model.number="form.target_id"
                      required
                      class="w-full h-11 px-3.5 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                    >
                      <option :value="null" disabled>
                        {{ form.target_type === 'room' ? 'Selecione uma sala…' : 'Selecione uma pessoa…' }}
                      </option>
                      <option v-for="opt in targetOptions" :key="opt.value" :value="opt.value">
                        {{ opt.label }}
                      </option>
                    </select>
                    <p v-if="form.target_type === 'disabled'" class="text-xs text-n-slate-10 mt-2">
                      Quando desativado, esse evento não dispara nenhuma mensagem da Beatriz no Chat Interno.
                    </p>
                  </div>

                  <!-- Body -->
                  <div>
                    <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">
                      Mensagem
                    </label>
                    <textarea
                      ref="bodyTextareaRef"
                      v-model="form.body"
                      required
                      rows="12"
                      maxlength="4000"
                      class="w-full min-h-[260px] px-3.5 py-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed font-mono"
                    />
                    <p class="text-xs text-n-slate-10 mt-1.5 leading-relaxed">
                      Use <code class="px-1 py-0.5 rounded bg-n-alpha-2 font-mono text-[11px]">%&#123;variavel&#125;</code> pra inserir dados dinâmicos. Variáveis disponíveis estão na coluna ao lado.
                    </p>
                  </div>

                  <!-- Toggle ativo -->
                  <div class="flex items-center justify-between gap-4 px-4 py-3.5 rounded-lg bg-n-alpha-1 border border-n-weak">
                    <div class="min-w-0 pr-2">
                      <div class="text-sm font-semibold text-n-slate-12 leading-tight">Template ativo</div>
                      <div class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                        Quando desativado, esse aviso não vai pro Chat Interno mesmo se o gatilho disparar.
                      </div>
                    </div>
                    <button
                      type="button"
                      role="switch"
                      :aria-checked="form.enabled"
                      class="relative shrink-0 inline-flex h-6 w-11 flex-none items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-woot-500/30 focus:ring-offset-2 focus:ring-offset-n-solid-1 p-0 border-0"
                      :class="form.enabled ? 'bg-woot-500' : 'bg-n-slate-6'"
                      @click="form.enabled = !form.enabled"
                    >
                      <span
                        class="absolute left-0.5 inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform"
                        :class="form.enabled ? 'translate-x-5' : 'translate-x-0'"
                      />
                    </button>
                  </div>
                </div>

                <!-- Coluna direita (1/3): variáveis + preview -->
                <aside class="space-y-5">
                  <div>
                    <h3 class="text-sm font-semibold text-n-slate-12 mb-2">Variáveis disponíveis</h3>
                    <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">Clique numa pra inserir no cursor da mensagem.</p>
                    <div class="flex flex-wrap gap-1.5">
                      <button
                        v-for="v in availableVars"
                        :key="v"
                        type="button"
                        class="px-2 py-1 text-xs font-mono rounded-md bg-n-alpha-2 text-n-slate-12 hover:bg-woot-50 hover:text-woot-700 transition-colors border border-n-weak"
                        @click="insertVar(v)"
                      >
                        %&#123;{{ v }}&#125;
                      </button>
                    </div>
                  </div>

                  <div>
                    <h3 class="text-sm font-semibold text-n-slate-12 mb-2">Preview</h3>
                    <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">Como a mensagem chega no chat (com dados de exemplo).</p>
                    <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-3.5 text-xs leading-relaxed text-n-slate-12 whitespace-pre-line min-h-[160px]">
                      {{ renderedPreview || 'A mensagem aparece aqui conforme você edita.' }}
                    </div>
                  </div>
                </aside>
              </div>
            </form>

            <footer class="flex-shrink-0 px-7 py-4 border-t border-n-weak flex items-center justify-end gap-3 bg-n-alpha-1">
              <button
                type="button"
                class="px-4 py-2.5 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                @click="closeModal"
              >
                Cancelar
              </button>
              <button
                type="button"
                :disabled="uiFlags.isUpdating || !form.name || !form.body || (form.target_type !== 'disabled' && !form.target_id)"
                class="inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-lg bg-woot-500 text-white hover:bg-woot-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors shadow-sm"
                @click="save"
              >
                <svg v-if="uiFlags.isUpdating" class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round"/></svg>
                Salvar alterações
              </button>
            </footer>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.2s ease;
}
.modal-enter-active > div,
.modal-leave-active > div {
  transition: transform 0.24s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.2s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
.modal-enter-from > div,
.modal-leave-to > div {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
}
</style>
