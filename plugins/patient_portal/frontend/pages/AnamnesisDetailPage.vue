<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseButton from '../components/BaseButton.vue';
import Badge from '../components/Badge.vue';
import EmptyState from '../components/EmptyState.vue';
import IconHeart from '../components/icons/IconHeart.vue';
import { anamnesesApi } from '../api/anamneses';
import { formatDate } from '../utils/format';

const route = useRoute();
const anamnesis = ref(null);
const loading = ref(true);

onMounted(async () => {
  try {
    anamnesis.value = await anamnesesApi.get(route.params.id);
  } catch (_) {
    /* fica null */
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <AppShell>
    <PageHeader title="Anamnese" back @back="$router.back()" />

    <div v-if="loading" class="pp-anam__loading">Carregando…</div>

    <div v-else-if="anamnesis" class="pp-anam">
      <section class="pp-anam__hero">
        <div class="pp-anam__hero-label">
          Versão {{ anamnesis.version_number }} ·
          {{ anamnesis.specialty || 'Anamnese' }}
        </div>
        <div class="pp-anam__hero-meta">
          {{ formatDate(anamnesis.finalized_at) }}
          <span v-if="anamnesis.professional">
            · {{ anamnesis.professional.name }}</span
          >
        </div>
      </section>

      <BaseCard v-if="anamnesis.chief_complaint" title="Queixa principal">
        <p class="pp-anam__text">{{ anamnesis.chief_complaint }}</p>
      </BaseCard>

      <BaseCard v-if="(anamnesis.allergies || []).length > 0" title="Alergias">
        <ul class="pp-anam__list">
          <li
            v-for="(a, i) in anamnesis.allergies"
            :key="i"
            class="pp-anam__list-item"
          >
            <div class="pp-anam__list-title">
              {{ a.substance || a.name }}
              <Badge v-if="a.severity === 'high'" variant="danger" size="sm">
                Severa
              </Badge>
              <Badge
                v-else-if="a.severity === 'medium'"
                variant="warning"
                size="sm"
              >
                Moderada
              </Badge>
            </div>
            <div
              v-if="a.reaction || a.description"
              class="pp-anam__list-detail"
            >
              {{ a.reaction || a.description }}
            </div>
          </li>
        </ul>
      </BaseCard>

      <BaseCard
        v-if="(anamnesis.current_medications || []).length > 0"
        title="Medicações em uso"
      >
        <ul class="pp-anam__list">
          <li
            v-for="(m, i) in anamnesis.current_medications"
            :key="i"
            class="pp-anam__list-item"
          >
            <div class="pp-anam__list-title">{{ m.name }}</div>
            <div v-if="m.alert" class="pp-anam__list-detail">{{ m.alert }}</div>
          </li>
        </ul>
      </BaseCard>

      <BaseCard v-if="anamnesis.surgical_history" title="Histórico cirúrgico">
        <p class="pp-anam__text">{{ anamnesis.surgical_history }}</p>
      </BaseCard>

      <BaseCard v-if="anamnesis.family_history" title="Histórico familiar">
        <p class="pp-anam__text">{{ anamnesis.family_history }}</p>
      </BaseCard>

      <BaseCard
        v-if="anamnesis.additional_notes"
        title="Observações adicionais"
      >
        <p class="pp-anam__text">{{ anamnesis.additional_notes }}</p>
      </BaseCard>

      <p class="pp-anam__footer">
        Esta anamnese é gerada pela clínica e exibida no portal apenas para sua
        consulta. Para atualizar dados, fale com a recepção.
      </p>
    </div>

    <EmptyState
      v-else
      title="Anamnese não encontrada"
      description="Esta anamnese pode não estar disponível ou sua clínica desabilitou a visualização."
    >
      <template #icon><IconHeart :size="28" /></template>
      <template #action>
        <BaseButton @click="$router.push({ name: 'health' })">
          Voltar
        </BaseButton>
      </template>
    </EmptyState>
  </AppShell>
</template>

<style scoped>
.pp-anam {
  padding: 16px var(--pp-content-pad-x);
  display: flex;
  flex-direction: column;
  gap: 14px;
}
@media (min-width: 1024px) {
  .pp-anam {
    max-width: 760px;
    gap: 18px;
  }
}
.pp-anam__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}

.pp-anam__hero {
  padding: 16px;
  border-radius: 14px;
  background: linear-gradient(135deg, #fee2e2 0%, #fecaca 100%);
  border: 1px solid #fca5a5;
}
.pp-anam__hero-label {
  font-size: 13px;
  font-weight: 700;
  color: #991b1b;
}
.pp-anam__hero-meta {
  font-size: 12px;
  color: #7f1d1d;
  margin-top: 4px;
}

.pp-anam__text {
  margin: 0;
  font-size: 14px;
  line-height: 1.5;
  color: var(--pp-color-text);
  white-space: pre-wrap;
}

.pp-anam__list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.pp-anam__list-item {
  padding-bottom: 10px;
  border-bottom: 1px solid var(--pp-color-border);
}
.pp-anam__list-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}
.pp-anam__list-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  font-size: 14px;
  color: var(--pp-color-text);
}
.pp-anam__list-detail {
  font-size: 12px;
  color: var(--pp-color-text-muted);
  margin-top: 2px;
}

.pp-anam__footer {
  text-align: center;
  padding: 8px 16px;
  font-size: 12px;
  color: var(--pp-color-text-muted);
  margin: 0;
}
</style>
