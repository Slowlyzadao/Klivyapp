<template>
  <AppShell>
    <PageHeader title="Termos clínicos" back @back="$router.back()" subtitle="Consentimentos para procedimentos" />

    <div class="pp-consents">
      <div v-if="consents.loading" class="pp-consents__loading">Carregando…</div>

      <template v-else>
        <!-- Pendentes -->
        <section v-if="consents.pending.length > 0">
          <h3 class="pp-consents__section-title pp-consents__section-title--warn">
            <IconInfo :size="14" /> Pendentes ({{ consents.pendingCount }})
          </h3>
          <ul class="pp-consents__list">
            <li v-for="c in consents.pending" :key="c.id">
              <router-link :to="{ name: 'consent-record-sign', params: { id: c.id } }" class="pp-consent-item pp-consent-item--pending">
                <div class="pp-consent-item__icon"><IconShield :size="20" /></div>
                <div class="pp-consent-item__body">
                  <div class="pp-consent-item__title">{{ c.title }}</div>
                  <div class="pp-consent-item__meta">Criado em {{ formatDate(c.created_at) }}</div>
                </div>
                <Badge variant="warning" size="sm">Aguardando</Badge>
              </router-link>
            </li>
          </ul>
        </section>

        <!-- Assinados -->
        <section v-if="consents.signed.length > 0">
          <h3 class="pp-consents__section-title">Histórico</h3>
          <ul class="pp-consents__list">
            <li v-for="c in consents.signed" :key="c.id">
              <router-link :to="{ name: 'consent-record-sign', params: { id: c.id } }" class="pp-consent-item">
                <div class="pp-consent-item__icon pp-consent-item__icon--ok"><IconCheck :size="20" /></div>
                <div class="pp-consent-item__body">
                  <div class="pp-consent-item__title">{{ c.title }}</div>
                  <div class="pp-consent-item__meta">Assinado em {{ formatDate(c.signed_at) }}</div>
                </div>
                <Badge variant="success" size="sm">Assinado</Badge>
              </router-link>
            </li>
          </ul>
        </section>

        <BaseCard v-if="consents.pending.length === 0 && consents.signed.length === 0">
          <EmptyState
            title="Nenhum termo registrado"
            description="A clínica envia termos de consentimento para procedimentos específicos quando necessário. Você verá aqui quando houver algum para assinar."
          >
            <template #icon><IconShield :size="28" /></template>
          </EmptyState>
        </BaseCard>
      </template>
    </div>
  </AppShell>
</template>

<script setup>
import { onMounted } from 'vue';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import Badge from '../components/Badge.vue';
import EmptyState from '../components/EmptyState.vue';
import IconShield from '../components/icons/IconShield.vue';
import IconCheck from '../components/icons/IconCheck.vue';
import IconInfo from '../components/icons/IconInfo.vue';
import { useConsentRecordsStore } from '../store/consent_records';
import { formatDate } from '../utils/format';

const consents = useConsentRecordsStore();

onMounted(() => { consents.fetch(); });
</script>

<style scoped>
.pp-consents { padding: 16px; display: flex; flex-direction: column; gap: 20px; }
.pp-consents__loading { padding: 32px; text-align: center; color: var(--pp-color-text-muted); font-size: 14px; }

.pp-consents__section-title {
  display: flex; align-items: center; gap: 6px;
  margin: 0 0 8px; font-size: 13px; font-weight: 700;
  color: var(--pp-color-text-muted); text-transform: uppercase; letter-spacing: .5px;
}
.pp-consents__section-title--warn { color: #92400e; }

.pp-consents__list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }

.pp-consent-item {
  display: flex; align-items: center; gap: 12px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  padding: 14px; text-decoration: none; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-consent-item:hover  { box-shadow: 0 4px 12px rgba(15, 23, 42, .06); border-color: var(--pp-color-primary); }
.pp-consent-item:active { transform: scale(0.99); }
.pp-consent-item--pending { border-color: #fde68a; background: #fffbeb; }

.pp-consent-item__icon {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  background: #fef3c7; color: #92400e;
}
.pp-consent-item__icon--ok { background: #d1fae5; color: #047857; }

.pp-consent-item__body { flex: 1; min-width: 0; }
.pp-consent-item__title { font-weight: 600; font-size: 14px; color: var(--pp-color-text); }
.pp-consent-item__meta  { font-size: 12px; color: var(--pp-color-text-muted); margin-top: 2px; }
</style>
