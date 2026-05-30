<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseButton from '../components/BaseButton.vue';
import { useDocumentsStore } from '../store/documents';
import { formatDate } from '../utils/format';

const router = useRouter();
const docs = useDocumentsStore();

const form = ref({ document_type: '', source_document_id: '', reason: '' });
const error = ref(null);
const submitting = ref(false);

const types = [
  { value: 'atestado', label: 'Atestado' },
  { value: 'receita', label: 'Receita' },
  { value: 'pedido_exame', label: 'Pedido de exame' },
  { value: 'declaracao', label: 'Declaração' },
  { value: 'encaminhamento', label: 'Encaminhamento' },
  { value: 'relatorio_clinico', label: 'Relatório clínico' },
  { value: 'outro', label: 'Outro' },
];

const priorDocs = computed(() => docs.items);
const hasPriorDocs = computed(() => priorDocs.value.length > 0);
const canSubmit = computed(
  () => form.value.document_type && form.value.reason.trim().length >= 5
);

onMounted(() => {
  // Garante que a lista de docs do paciente está carregada (pra mostrar refs)
  if (docs.items.length === 0) docs.fetch();
});

async function onSubmit() {
  error.value = null;
  submitting.value = true;
  try {
    await docs.requestDocument({
      document_type: form.value.document_type,
      source_document_id: form.value.source_document_id || null,
      reason: form.value.reason.trim(),
    });
    router.replace({ name: 'health', query: { requested: '1' } });
  } catch (e) {
    error.value = e.message;
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <AppShell>
    <PageHeader title="Solicitar documento" back @back="$router.back()" />

    <div class="pp-doc-req">
      <p class="pp-doc-req__intro">
        Pediu um atestado, receita ou recibo? Solicite e a clínica retorna com o
        documento.
      </p>

      <BaseCard title="O que você precisa?">
        <label class="pp-doc-req__field">
          <span class="pp-doc-req__label">Tipo de documento</span>
          <select v-model="form.document_type" class="pp-doc-req__select">
            <option value="">Selecione…</option>
            <option v-for="t in types" :key="t.value" :value="t.value">
              {{ t.label }}
            </option>
          </select>
        </label>

        <label v-if="hasPriorDocs" class="pp-doc-req__field">
          <span class="pp-doc-req__label">Referência (opcional)</span>
          <select v-model="form.source_document_id" class="pp-doc-req__select">
            <option value="">Não — quero um novo</option>
            <option v-for="d in priorDocs" :key="d.id" :value="d.id">
              {{ d.title }} ({{ formatDate(d.created_at) }})
            </option>
          </select>
        </label>

        <label class="pp-doc-req__field">
          <span class="pp-doc-req__label">Por que precisa? (obrigatório)</span>
          <textarea
            v-model="form.reason"
            rows="3"
            placeholder="Ex: empresa pediu atestado da última consulta; preciso da receita renovada; precisar de 2ª via para auxílio."
            class="pp-doc-req__textarea"
            maxlength="500"
          />
        </label>
      </BaseCard>

      <p v-if="error" class="pp-doc-req__error">{{ error }}</p>

      <BaseButton
        block
        size="lg"
        :loading="submitting"
        :disabled="!canSubmit"
        @click="onSubmit"
      >
        Enviar pedido
      </BaseButton>

      <p class="pp-doc-req__hint">
        A clínica analisa em até 2 dias úteis. Você recebe o documento aqui
        mesmo ou aviso de recusa com motivo.
      </p>
    </div>
  </AppShell>
</template>

<style scoped>
.pp-doc-req {
  padding: 16px var(--pp-content-pad-x);
  display: flex;
  flex-direction: column;
  gap: 16px;
}
@media (min-width: 1024px) {
  .pp-doc-req {
    max-width: 640px;
  }
}
.pp-doc-req__intro {
  margin: 0;
  font-size: 14px;
  color: var(--pp-color-text-muted);
}

.pp-doc-req__field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 12px;
}
.pp-doc-req__field:last-child {
  margin-bottom: 0;
}
.pp-doc-req__label {
  font-size: 12px;
  font-weight: 600;
  color: var(--pp-color-text-muted);
}
.pp-doc-req__select,
.pp-doc-req__textarea {
  width: 100%;
  padding: 10px 12px;
  border-radius: 10px;
  border: 1px solid var(--pp-color-border);
  font-size: 14px;
  font-family: inherit;
  resize: vertical;
}

.pp-doc-req__error {
  color: #b91c1c;
  font-size: 13px;
  margin: 0;
}
.pp-doc-req__hint {
  text-align: center;
  font-size: 12px;
  color: var(--pp-color-text-muted);
  margin: 0;
}
</style>
