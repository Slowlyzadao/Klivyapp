<script setup>
// Página de edição de template — orquestra toolbar + canvas TipTap + sidebar
// + autosave + atalhos.
//
// Carrega o template via store no mount (rota `documents_dashboard_edit`
// passa o id). Modificações locais ficam num ref `draft` e são salvas via
// debounce. Cmd/Ctrl+S força save imediato.

import { ref, reactive, computed, watch, nextTick, onMounted, onBeforeUnmount, useTemplateRef } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useAlert } from 'dashboard/composables';
import { useDocumentTemplatesStore } from '../../stores/documentTemplates';

import EditorToolbar from '../../components/editor/EditorToolbar.vue';
import TipTapEditor from '../../components/editor/TipTapEditor.vue';
import EditorSidebar from '../../components/editor/EditorSidebar.vue';
import PaperContainer from '../../components/editor/PaperContainer.vue';
import ConfirmDialog from '../../components/modals/ConfirmDialog.vue';
import { useConfirm } from '../../composables/useDialogs';
import { useSidebarForceCollapse } from 'dashboard/components-next/sidebar/provider';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const vuexStore = useStore();
const store = useDocumentTemplatesStore();
const { variables, folders } = storeToRefs(store);

// Diálogo de confirmação (substitui window.confirm ao sair com alterações).
const { confirmState, confirm, onConfirm, onCancel } = useConfirm();

// Editor é tela-cheia: colapsa a sidebar do dashboard ao entrar e libera ao
// sair (não-destrutivo — preserva a largura escolhida pelo usuário).
const { forceCollapse, releaseCollapse } = useSidebarForceCollapse();

const draft = ref(null);
const loading = ref(true);
const saving = ref(false);
const savedAt = ref(null);
const error = ref(null);

const editorRef = useTemplateRef('editor');
const titleInputRef = useTemplateRef('titleInput');

// Sidebar de configurações/variáveis: coluna fixa no desktop, drawer off-canvas
// em telas estreitas (≤900px), onde a coluna espremeria o papel a uma faixa
// inutilizável. Alternado pelo botão do header (só visível no mobile via CSS).
const sidebarOpen = ref(false);

const accountId = computed(() => route.params.accountId);

// ── Dados reais do paciente/profissional na aba "Variáveis" ─────────────
// Ao escolher um paciente (e opcionalmente um profissional), resolvemos as
// variáveis e mostramos o VALOR REAL ao lado de cada uma no painel lateral
// "Variáveis" (EditorSidebar). Não toca na folha nem no content_json.
const previewState = reactive({ values: {} });
const previewPatientId = ref('');
const patientResults = ref([]);
const pickedPatient = ref(null);

// Profissional do preview: resolve `professional.*` (CRM, especialidade, etc.)
// pro profissional escolhido. Vazio = usuário logado (default no backend).
const previewProfessionalId = ref('');
const professionalOptions = computed(() =>
  (vuexStore.getters['agents/getAgents'] || []).map(a => ({
    value: a.id,
    label: a.name,
    avatar: a.avatar_url || a.thumbnail || '',
  }))
);

const patientOptions = computed(() => {
  const opts = patientResults.value.map(p => ({
    value: p.id,
    label: p.name || p.full_name || `#${p.id}`,
    avatar: p.avatar_url || '',
  }));
  // Mantém o paciente escolhido visível mesmo após uma nova busca.
  if (
    pickedPatient.value &&
    !opts.some(o => o.value === pickedPatient.value.value)
  ) {
    opts.unshift(pickedPatient.value);
  }
  return opts;
});

const searchPatients = async query => {
  try {
    const res = await PatientsAPI.get({ search: query || '', page: 1 });
    const raw =
      res.data?.payload || res.data?.data || res.data?.patients || res.data || [];
    patientResults.value = Array.isArray(raw) ? raw : raw.data || raw.payload || [];
  } catch (e) {
    patientResults.value = [];
  }
};

const loadPreviewValues = async () => {
  if (!previewPatientId.value) return;
  try {
    previewState.values = await store.fetchPreviewValues(
      previewPatientId.value,
      previewProfessionalId.value
    );
  } catch (e) {
    useAlert(t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_ERROR'));
    previewState.values = {};
  }
};

const onPickPatient = id => {
  previewPatientId.value = id;
  const opt = patientOptions.value.find(o => o.value === id);
  if (opt) pickedPatient.value = opt;
  // Carrega os valores resolvidos pro painel lateral "Variáveis".
  if (id) loadPreviewValues();
  else previewState.values = {};
};

const onPickProfessional = id => {
  previewProfessionalId.value = id;
  // Recarrega pra atualizar professional.* (CRM/especialidade) do escolhido.
  if (previewPatientId.value) loadPreviewValues();
};

onMounted(() => {
  searchPatients('');
  // Garante a lista de agentes carregada pro seletor de profissional do preview.
  vuexStore.dispatch('agents/get');
});

// Template Klivy (account_id NULL) é read-only pra esta clínica. Em vez de
// bloquear a edição, fazemos clone-on-edit: a primeira modificação cria uma
// cópia na conta e passa a editar a cópia. is_klivy vem do serializer.
const isReadOnly = computed(() => Boolean(draft.value?.is_klivy));

// ── Edição inline do título ─────────────────────────────────────────────
const editingTitle = ref(false);
const titleDraft = ref('');

const startEditingTitle = async () => {
  if (!draft.value) return;
  titleDraft.value = draft.value.name || '';
  editingTitle.value = true;
  await nextTick();
  titleInputRef.value?.focus();
  titleInputRef.value?.select();
};

const commitTitle = () => {
  if (!editingTitle.value) return;
  editingTitle.value = false;
  const next = titleDraft.value.trim();
  if (!next || next === draft.value.name) return;
  onSettingsChange({ name: next });
};

const cancelTitle = () => {
  editingTitle.value = false;
};

const headerVersion = computed(() => `v${draft.value?.version || 1}`);

const lastSavedLabel = computed(() => {
  if (saving.value) return t('DOCUMENT_TEMPLATES.EDITOR.SAVING');
  if (error.value) return t('DOCUMENT_TEMPLATES.EDITOR.SAVE_ERROR');
  if (!savedAt.value) return '';
  return t('DOCUMENT_TEMPLATES.EDITOR.SAVED_NOW');
});

// ── Boot ──────────────────────────────────────────────────────────────────
onMounted(async () => {
  try {
    await Promise.all([
      store.fetchFolders(),
      store.ensureVariables(),
    ]);
    const tpl = await store.fetchTemplate(route.params.id);
    draft.value = { ...tpl };
  } catch (e) {
    error.value = e.message;
    useAlert(e.message);
  } finally {
    loading.value = false;
  }
});

// ── Autosave com retry exponencial ───────────────────────────────────────
// Debounce 1.5s pra agrupar digitação. Quando o save falha, mantém o estado
// `dirty` e tenta de novo com backoff (2s → 5s → 10s). Após 3 falhas, mostra
// botão "Tentar novamente" inline pra o user. Estado `dirty` previne fechar
// a aba/rota com mudanças não salvas.
// Debounce do autosave: espera o usuário parar de digitar por este intervalo
// antes de salvar. 2.5s é o padrão de editores de documento (calmo o bastante
// pra não disparar a cada micro-pausa, curto o bastante pra não perder muito).
const AUTOSAVE_DEBOUNCE_MS = 2500;
const RETRY_DELAYS_MS = [2000, 5000, 10_000];
let saveTimer = null;
let retryTimer = null;
// Edição que chegou enquanto um save já estava em voo. Garante que ela seja
// reenviada quando o PATCH atual terminar (fecha a janela de lost-update).
let pendingSave = false;
const dirty = ref(false);
const retryAttempt = ref(0);

const scheduleSave = () => {
  dirty.value = true;
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(saveNow, AUTOSAVE_DEBOUNCE_MS);
};

// Clone-on-edit: se o template é Klivy (read-only), a primeira tentativa de
// salvar clona pra conta e passa a editar a cópia — preservando as edições
// locais (que são enviadas no PATCH seguinte). Atualiza a URL sem remontar.
// Requer admin (clone_to_account? na policy); senão propaga o erro.
const ensureWritable = async () => {
  if (!isReadOnly.value) return;

  const clone = await store.cloneKlivyTemplate(draft.value.id);
  draft.value.id = clone.id;
  draft.value.account_id = clone.account_id;
  draft.value.is_klivy = false;
  draft.value.is_cloned = true;
  draft.value.source = 'cloned';
  draft.value.version = clone.version;

  await router.replace({
    name: 'documents_dashboard_edit',
    params: { accountId: accountId.value, id: clone.id },
  });
};

const saveNow = async ({ manual = false } = {}) => {
  if (!draft.value) return;
  // Save já em voo: marca que há edição nova pendente e sai. O finally
  // re-agenda quando o PATCH atual terminar — sem isso, uma edição feita
  // durante o request (seguida de pausa) ficava dirty e nunca era reenviada.
  if (saving.value) { pendingSave = true; return; }
  saving.value = true;
  error.value = null;
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null; }

  try {
    await ensureWritable();

    const updated = await store.updateTemplate(draft.value.id, {
      name: draft.value.name,
      description: draft.value.description,
      document_type: draft.value.document_type,
      folder_id: draft.value.folder_id,
      paper_size: draft.value.paper_size,
      orientation: draft.value.orientation,
      status: draft.value.status,
      content_json: draft.value.content_json,
    });
    draft.value.version = updated.version;
    savedAt.value = new Date();
    dirty.value = false;
    retryAttempt.value = 0;
  } catch (e) {
    const status = e.response?.status;
    error.value = e.response?.data?.errors?.join(', ') || e.message || 'Erro desconhecido';

    // Erros de autorização (401/403) NÃO são retentáveis — retry só geraria
    // spam de 401. Mostra alerta uma vez e para.
    if (status === 401 || status === 403) {
      useAlert(t('DOCUMENT_TEMPLATES.EDITOR.NO_PERMISSION'));
    } else if (!manual && retryAttempt.value < RETRY_DELAYS_MS.length) {
      // Backoff até 3 vezes pra erros transitórios (rede, 5xx). Save manual
      // (Cmd+S/botão) não dispara retry — o user decide.
      const delay = RETRY_DELAYS_MS[retryAttempt.value];
      retryAttempt.value += 1;
      retryTimer = setTimeout(saveNow, delay);
    } else if (!manual) {
      useAlert(t('DOCUMENT_TEMPLATES.EDITOR.SAVE_FAILED_AFTER_RETRIES'));
    }
  } finally {
    saving.value = false;
    // Chegou edição durante o PATCH em voo? Re-agenda pra reenviar o conteúdo
    // mais novo. Em caso de erro, o retryTimer já cuida disso (reenvia o
    // content_json atual), então não duplicamos o agendamento.
    if (pendingSave) {
      pendingSave = false;
      if (!error.value) scheduleSave();
    }
  }
};

const manualRetry = () => {
  retryAttempt.value = 0;
  saveNow({ manual: true });
};

// Vue Router guard — bloqueia leave quando há mudanças não salvas. O guard
// pode ser async: mostra o ConfirmDialog e aguarda a escolha do user.
onBeforeRouteLeave(async () => {
  if (!dirty.value) return true;
  return await confirm({
    title: t('DOCUMENT_TEMPLATES.EDITOR.UNSAVED_TITLE'),
    message: t('DOCUMENT_TEMPLATES.EDITOR.UNSAVED_CHANGES_LEAVE'),
    confirmLabel: t('DOCUMENT_TEMPLATES.EDITOR.UNSAVED_CONFIRM'),
    cancelLabel: t('DOCUMENT_TEMPLATES.EDITOR.UNSAVED_CANCEL'),
    variant: 'danger',
  });
});

// beforeunload — bloqueia refresh/close da aba quando há mudanças não salvas.
const onBeforeUnload = e => {
  if (!dirty.value) return undefined;
  e.preventDefault();
  e.returnValue = '';
  return '';
};

// ── Atalhos de teclado ───────────────────────────────────────────────────
const onKeyDown = (e) => {
  const isMod = e.metaKey || e.ctrlKey;
  if (isMod && e.key === 's') {
    e.preventDefault();
    saveNow({ manual: true });
    return;
  }
  // Cmd/Ctrl + / → insere "/" no editor pra acionar o suggestion popover
  // (mesmo comportamento do Notion/Linear). Funciona mesmo se o foco está
  // fora do TipTap — focamos o editor antes.
  if (isMod && e.key === '/') {
    e.preventDefault();
    const editor = editorRef.value?.getEditor();
    if (editor) {
      editor.chain().focus().insertContent('/').run();
    }
  }
};

onMounted(() => {
  document.addEventListener('keydown', onKeyDown);
  window.addEventListener('beforeunload', onBeforeUnload);
  forceCollapse();
});
onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKeyDown);
  window.removeEventListener('beforeunload', onBeforeUnload);
  releaseCollapse();
  if (saveTimer) clearTimeout(saveTimer);
  if (retryTimer) clearTimeout(retryTimer);
});

// ── Handlers ────────────────────────────────────────────────────────────
const onContentChange = (json) => {
  if (!draft.value) return;
  draft.value.content_json = json;
  scheduleSave();
};

const onSettingsChange = (patch) => {
  if (!draft.value) return;
  Object.assign(draft.value, patch);
  scheduleSave();
};

const insertVariableFromSidebar = (variable) => {
  editorRef.value?.insertVariable({
    key: variable.key,
    label: variable.label,
    fallback: '_______',
  });
};

const goBack = () => {
  router.push({ name: 'documents_dashboard_index' });
};

const getVariablesFactory = () => () => variables.value;
</script>

<template>
  <div class="template-editor">
    <header class="template-editor__header">
      <button
        type="button"
        class="template-editor__back-btn"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left" />
        {{ t('DOCUMENT_TEMPLATES.EDITOR.BACK') }}
      </button>

      <h1 class="template-editor__title">
        <span class="i-lucide-file-text template-editor__title-icon" />
        <input
          v-if="editingTitle"
          ref="titleInput"
          v-model="titleDraft"
          type="text"
          class="template-editor__title-input reset-base"
          maxlength="120"
          @keydown.enter.prevent="commitTitle"
          @keydown.esc.prevent="cancelTitle"
          @blur="commitTitle"
        />
        <button
          v-else-if="draft"
          type="button"
          class="template-editor__title-name"
          :title="t('DOCUMENT_TEMPLATES.EDITOR.EDIT_TITLE_HINT')"
          @dblclick="startEditingTitle"
        >
          {{ draft.name }}
        </button>
        <span v-else>{{ t('DOCUMENT_TEMPLATES.EDITOR.LOADING') }}</span>
        <span v-if="draft" class="template-editor__version">{{ headerVersion }}</span>
        <span v-if="isReadOnly" class="template-editor__klivy-flag">
          {{ t('DOCUMENT_TEMPLATES.EDITOR.KLIVY_READONLY_HINT') }}
        </span>
      </h1>

      <div class="template-editor__status">
        <span v-if="saving" class="i-lucide-loader-circle template-editor__status-icon" />
        <span v-else-if="error" class="i-lucide-triangle-alert template-editor__status-icon--error" />
        <span v-else-if="savedAt" class="i-lucide-check template-editor__status-icon--ok" />
        <span :title="error || ''">{{ lastSavedLabel }}</span>
        <button
          v-if="error && !saving"
          type="button"
          class="template-editor__retry-btn"
          @click="manualRetry"
        >
          {{ t('DOCUMENT_TEMPLATES.EDITOR.RETRY') }}
        </button>
      </div>

      <!-- Preview ao vivo (ao lado do Salvar): escolhe paciente real e
           alterna entre chips {{var}} e os valores resolvidos. -->
      <div v-if="draft" class="template-editor__preview-controls">
        <FormSelect
          class="template-editor__preview-patient"
          :model-value="previewPatientId"
          :options="patientOptions"
          :placeholder="t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_PATIENT_PLACEHOLDER')"
          searchable
          :search-placeholder="t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_PATIENT_SEARCH')"
          :no-options-text="t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_PATIENT_EMPTY')"
          @update:model-value="onPickPatient"
          @search-change="searchPatients"
        >
          <template #selected="{ option }">
            <template v-if="option">
              <Avatar :name="option.label" :src="option.avatar || ''" :size="18" />
              <span class="template-editor__preview-opt-label">{{ option.label }}</span>
            </template>
            <span v-else class="template-editor__preview-ph">
              {{ t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_PATIENT_PLACEHOLDER') }}
            </span>
          </template>
          <template #option="{ option }">
            <Avatar :name="option.label" :src="option.avatar || ''" :size="20" />
            <span class="template-editor__preview-opt-label">{{ option.label }}</span>
          </template>
        </FormSelect>

        <!-- Profissional do preview (resolve professional.* — CRM, etc.).
             Vazio = usuário logado. -->
        <FormSelect
          class="template-editor__preview-professional"
          :model-value="previewProfessionalId"
          :options="professionalOptions"
          :placeholder="t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_PROFESSIONAL_PLACEHOLDER')"
          auto-searchable
          @update:model-value="onPickProfessional"
        >
          <template #selected="{ option }">
            <template v-if="option">
              <Avatar :name="option.label" :src="option.avatar || ''" :size="18" />
              <span class="template-editor__preview-opt-label">{{ option.label }}</span>
            </template>
            <span v-else class="template-editor__preview-ph">
              {{ t('DOCUMENT_TEMPLATES.EDITOR.PREVIEW_PROFESSIONAL_PLACEHOLDER') }}
            </span>
          </template>
          <template #option="{ option }">
            <Avatar :name="option.label" :src="option.avatar || ''" :size="20" />
            <span class="template-editor__preview-opt-label">{{ option.label }}</span>
          </template>
        </FormSelect>
      </div>

      <!-- Toggle do drawer de configurações (só aparece em telas estreitas). -->
      <button
        type="button"
        class="template-editor__sidebar-toggle"
        :class="{ 'is-active': sidebarOpen }"
        :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.TAB_SETTINGS')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.TAB_SETTINGS')"
        :aria-expanded="sidebarOpen"
        @click="sidebarOpen = !sidebarOpen"
      >
        <span class="i-lucide-settings-2" />
      </button>

      <button
        type="button"
        class="template-editor__save-btn"
        :disabled="!dirty || saving"
        @click="saveNow({ manual: true })"
      >
        <span class="i-lucide-check" />
        {{ t('DOCUMENT_TEMPLATES.EDITOR.SAVE') }}
      </button>
    </header>

    <EditorToolbar
      v-if="draft && editorRef?.getEditor()"
      :editor="editorRef.getEditor()"
    />

    <div class="template-editor__body" :class="{ 'is-drawer-open': sidebarOpen }">
      <main class="template-editor__canvas">
        <PaperContainer
          v-if="draft"
          :paper-size="draft.paper_size || 'A4'"
          :orientation="draft.orientation || 'portrait'"
        >
          <TipTapEditor
            ref="editor"
            :model-value="draft.content_json"
            :get-variables="getVariablesFactory()"
            @update:model-value="onContentChange"
          />
        </PaperContainer>
        <div v-else class="template-editor__loading">
          <span class="i-lucide-loader-circle" />
        </div>
      </main>

      <!-- Backdrop do drawer (só no mobile, quando aberto). Fecha ao clicar. -->
      <div
        class="template-editor__scrim"
        @click="sidebarOpen = false"
      />

      <EditorSidebar
        v-if="draft"
        class="template-editor__sidebar"
        :class="{ 'is-open': sidebarOpen }"
        :template="draft"
        :folders="folders"
        :preview-values="previewState.values"
        :selected-patient-id="previewPatientId"
        @update:settings="onSettingsChange"
        @insert-variable="insertVariableFromSidebar"
      />
    </div>

    <ConfirmDialog
      v-bind="confirmState"
      @confirm="onConfirm"
      @cancel="onCancel"
    />
  </div>
</template>

<!--
  Tokens M3 Klivy carregados GLOBALMENTE (não-scoped) pra cobrir popovers
  teleportados (VariablePickerMenu via tippy, etc).
-->
<style lang="scss">
@use '../../styles/klivy-tokens';
</style>

<style lang="scss" scoped>
@use '../../styles/editor/editor-page';
</style>
