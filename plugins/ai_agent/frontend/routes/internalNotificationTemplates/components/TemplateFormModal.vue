<script setup>
// FE-4 (auditoria 2026-05-18): extraído do Index.vue (516 LOC).
// UX-fix 2026-05-19:
//   - Seletor de "Onde enviar" agora usa o componente Tabs/TabsItem padrão
//     do Chatwoot (era 3 botões custom com classes Tailwind soltas).
//   - Modal vira full-screen em mobile (<lg). Antes era card fixo com
//     `max-w-5xl max-h-[92vh]` que apertava demais o conteúdo em telas
//     pequenas. Em desktop preserva o look anterior.
// FE-16/17 (i18n 2026-05-19): strings migradas para `AI_AGENT.TEMPLATES.*`.
import { ref, computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import UserPickerSelect from '@plugins/beclinic_core/frontend/components/UserPickerSelect.vue';
import Tabs from 'dashboard/components/ui/Tabs/Tabs.vue';
import TabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  // `editingTemplate` é o registro completo (vem do store no pai) — usamos
  // pra extrair `event_label`, `available_vars` e `detector_status`. Pode
  // ser null se ainda não houver template selecionado (modal fechado).
  editingTemplate: { type: Object, default: null },
  // `form` é reactive() criado no pai. Vue 3 preserva reatividade através
  // de props quando o objeto é reactive — mutar `form.body = '...'` aqui
  // dispara watchers no pai.
  form: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
  // catalog vem do getter `aiAgentInternalNotificationTemplates/getCatalog`.
  // Usado pra montar o select de "Onde enviar" (rooms ou users).
  catalog: { type: Object, required: true },
});

const emit = defineEmits(['update:show', 'save']);

const { t } = useI18n();

const bodyTextareaRef = ref(null);

const TARGET_TYPE_OPTIONS = computed(() => [
  { value: 'room',     label: t('AI_AGENT.TEMPLATES.FORM.TARGET_TYPE_ROOM') },
  { value: 'user',     label: t('AI_AGENT.TEMPLATES.FORM.TARGET_TYPE_USER') },
  { value: 'disabled', label: t('AI_AGENT.TEMPLATES.FORM.TARGET_TYPE_DISABLED') },
]);

// Tabs/TabsItem usa índice (não string) pra controlar a aba ativa.
// Convertendo target_type ↔ index pra interoperar.
const targetTabIndex = computed({
  get: () => TARGET_TYPE_OPTIONS.value.findIndex(o => o.value === props.form.target_type),
  set: idx => {
    const newType = TARGET_TYPE_OPTIONS.value[idx]?.value;
    if (newType && newType !== props.form.target_type) {
      props.form.target_type = newType;
      props.form.target_id = null;
    }
  },
});

const availableVars = computed(() => props.editingTemplate?.available_vars || []);

const targetOptions = computed(() => {
  if (props.form.target_type === 'room') {
    return props.catalog.rooms.map(r => ({
      value: r.id,
      label: r.system_role ? `${r.name}${t('AI_AGENT.TEMPLATES.FORM.TARGET_ROOM_SYSTEM_SUFFIX')}` : r.name,
    }));
  }
  return [];
});

// Catalog dos users vem só com `{ id, name }`. UserPickerSelect aceita
// `avatar_url` e `badge` opcionais — se o backend passar a expor, vira
// automático. Hoje: avatar gera iniciais pelo nome (Avatar do core).
const userOptions = computed(() => props.catalog.users || []);

const detectorActive = computed(() => {
  const s = props.editingTemplate?.detector_status;
  return s === 'active' || s === ':active';
});

const insertVar = varName => {
  const ta = bodyTextareaRef.value;
  if (!ta) return;
  const start = ta.selectionStart;
  const end = ta.selectionEnd;
  const placeholder = `%{${varName}}`;
  props.form.body = props.form.body.slice(0, start) + placeholder + props.form.body.slice(end);
  nextTick(() => {
    const pos = start + placeholder.length;
    ta.focus();
    ta.setSelectionRange(pos, pos);
  });
};

// Preview do body com variáveis simuladas (pra clínica ver como vai ficar).
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
  return props.form.body.replace(/%\{(\w+)\}/g, (_m, k) => FAKE_VARS[k] || `[${k}?]`);
});

const closeModal = () => emit('update:show', false);
const onSave = () => emit('save');

// Lock do scroll do body quando modal abre — preserva comportamento original.
watch(() => props.show, val => {
  document.body.style.overflow = val ? 'hidden' : '';
});
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="show"
        class="fixed inset-0 z-50 flex items-stretch justify-center bg-black/40 backdrop-blur-sm lg:items-center lg:p-4"
        @click.self="closeModal"
      >
        <div
          class="bg-n-solid-1 shadow-2xl w-full h-full flex flex-col overflow-hidden lg:rounded-2xl lg:max-w-5xl lg:max-h-[92vh] lg:h-auto"
          @click.stop
        >
          <header class="flex-shrink-0 px-7 py-5 border-b border-n-weak flex items-start justify-between gap-4">
            <div class="min-w-0">
              <h2 class="text-lg font-semibold text-n-slate-12 leading-tight">
                {{ $t('AI_AGENT.TEMPLATES.FORM.TITLE') }}
              </h2>
              <p class="text-xs text-n-slate-10 mt-1">
                {{ editingTemplate?.event_label }}
                <span v-if="!detectorActive" class="ml-2 px-1.5 py-0.5 rounded text-[10px] font-medium" style="color: #b45309; background: #fef3c7;">
                  {{ $t('AI_AGENT.TEMPLATES.FORM.DETECTOR_NOT_ACTIVE_BADGE') }}
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
          <form class="flex-1 overflow-y-auto px-7 py-6" @submit.prevent="onSave">
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <!-- Coluna esquerda (2/3) -->
              <div class="lg:col-span-2 space-y-5">
                <!-- Nome -->
                <div>
                  <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">{{ $t('AI_AGENT.TEMPLATES.FORM.NAME_LABEL') }}</label>
                  <input
                    v-model="form.name"
                    type="text"
                    required
                    maxlength="120"
                    class="w-full h-11 px-3.5 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                  >
                </div>

                <!-- Destino: usa o componente Tabs padrão do Chatwoot -->
                <div>
                  <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">{{ $t('AI_AGENT.TEMPLATES.FORM.TARGET_LABEL') }}</label>
                  <Tabs
                    :index="targetTabIndex"
                    class="mb-3"
                    @change="targetTabIndex = $event"
                  >
                    <TabsItem
                      v-for="(opt, idx) in TARGET_TYPE_OPTIONS"
                      :key="opt.value"
                      :index="idx"
                      :name="opt.label"
                      :show-badge="false"
                      is-compact
                    />
                  </Tabs>
                  <!-- Aba "DM com pessoa específica": picker com avatar+badge.
                       Aba "Sala do Chat Interno": FormSelect simples (rooms já
                       trazem `system_role` suffix no label). -->
                  <UserPickerSelect
                    v-if="form.target_type === 'user'"
                    v-model="form.target_id"
                    :users="userOptions"
                    :placeholder="$t('AI_AGENT.TEMPLATES.FORM.TARGET_PLACEHOLDER_USER')"
                    auto-searchable
                  />
                  <FormSelect
                    v-else-if="form.target_type === 'room'"
                    v-model="form.target_id"
                    :options="targetOptions"
                    :placeholder="$t('AI_AGENT.TEMPLATES.FORM.TARGET_PLACEHOLDER_ROOM')"
                    auto-searchable
                  />
                  <p v-else class="text-xs text-n-slate-10 mt-2">
                    {{ $t('AI_AGENT.TEMPLATES.FORM.TARGET_DISABLED_HELP') }}
                  </p>
                </div>

                <!-- Body -->
                <div>
                  <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">
                    {{ $t('AI_AGENT.TEMPLATES.FORM.BODY_LABEL') }}
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
                    {{ $t('AI_AGENT.TEMPLATES.FORM.BODY_HELP_PREFIX') }}<code class="px-1 py-0.5 rounded bg-n-alpha-2 font-mono text-[11px]">%&#123;variavel&#125;</code>{{ $t('AI_AGENT.TEMPLATES.FORM.BODY_HELP_SUFFIX') }}
                  </p>
                </div>

                <!-- Toggle ativo -->
                <div class="flex items-center justify-between gap-4 px-4 py-3.5 rounded-lg bg-n-alpha-1 border border-n-weak">
                  <div class="min-w-0 pr-2">
                    <div class="text-sm font-semibold text-n-slate-12 leading-tight">{{ $t('AI_AGENT.TEMPLATES.FORM.ENABLED_TITLE') }}</div>
                    <div class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                      {{ $t('AI_AGENT.TEMPLATES.FORM.ENABLED_HELP') }}
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
                  <h3 class="text-sm font-semibold text-n-slate-12 mb-2">{{ $t('AI_AGENT.TEMPLATES.FORM.VARS_TITLE') }}</h3>
                  <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">{{ $t('AI_AGENT.TEMPLATES.FORM.VARS_HELP') }}</p>
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
                  <h3 class="text-sm font-semibold text-n-slate-12 mb-2">{{ $t('AI_AGENT.TEMPLATES.FORM.PREVIEW_TITLE') }}</h3>
                  <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">{{ $t('AI_AGENT.TEMPLATES.FORM.PREVIEW_HELP') }}</p>
                  <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-3.5 text-xs leading-relaxed text-n-slate-12 whitespace-pre-line min-h-[160px]">
                    {{ renderedPreview || $t('AI_AGENT.TEMPLATES.FORM.PREVIEW_EMPTY') }}
                  </div>
                </div>
              </aside>
            </div>
          </form>

          <footer class="flex-shrink-0 px-7 py-4 border-t border-n-weak flex items-center justify-end gap-3 bg-n-alpha-1">
            <BeclinicButton
              :label="$t('AI_AGENT.TEMPLATES.FORM.CANCEL')"
              variant="outline"
              color="slate"
              @click="closeModal"
            />
            <BeclinicButton
              :label="$t('AI_AGENT.TEMPLATES.FORM.SAVE')"
              :is-loading="isSaving"
              :disabled="isSaving || !form.name || !form.body || (form.target_type !== 'disabled' && !form.target_id)"
              @click="onSave"
            />
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
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
