<template>
  <AppShell>
    <PageHeader title="Saúde" subtitle="Documentos e histórico clínico" />

    <div class="pp-health">
      <!-- Termos clínicos pendentes (em destaque, se houver) -->
      <section v-if="consents.pendingCount > 0">
        <router-link :to="{ name: 'consent-records' }" class="pp-health__pending-banner">
          <div class="pp-health__pending-icon"><IconShield :size="20" /></div>
          <div class="pp-health__pending-body">
            <div class="pp-health__pending-title">
              {{ consents.pendingCount }} termo{{ consents.pendingCount > 1 ? 's' : '' }} aguardando sua assinatura
            </div>
            <div class="pp-health__pending-text">Revise e assine para liberar seus procedimentos.</div>
          </div>
          <IconChevronRight :size="18" />
        </router-link>
      </section>

      <!-- Documentos -->
      <section>
        <header class="pp-health__section-head">
          <h3 class="pp-health__section-title">Meus documentos</h3>
          <router-link :to="{ name: 'document-request' }" class="pp-health__cta">+ 2ª via</router-link>
        </header>

        <div v-if="docs.loading" class="pp-health__loading">Carregando…</div>

        <ul v-else-if="docs.items.length > 0" class="pp-health__doc-list">
          <li v-for="d in docs.items" :key="d.id">
            <DocumentCard :document="d" @open="onOpen" />
          </li>
        </ul>

        <BaseCard v-else>
          <EmptyState
            title="Nenhum documento ainda"
            description="Receitas, atestados e outros documentos emitidos pela clínica aparecem aqui."
          >
            <template #icon><IconDocument :size="28" /></template>
            <template #action>
              <router-link :to="{ name: 'document-request' }" class="pp-health__cta-primary">
                Solicitar documento
              </router-link>
            </template>
          </EmptyState>
        </BaseCard>

        <div v-if="pendingDocRequests.length > 0" class="pp-health__pending">
          <div class="pp-health__pending-title">
            <IconClock :size="14" /> Pedidos aguardando
          </div>
          <ul class="pp-health__pending-list">
            <li v-for="req in pendingDocRequests" :key="req.id" class="pp-health__pending-item">
              <div>
                <div class="pp-health__pending-line">
                  {{ req.source_document?.title || labelType(req.document_type) }}
                </div>
                <div class="pp-health__pending-notes">{{ req.reason }}</div>
              </div>
              <Badge variant="warning" size="sm">Aguardando</Badge>
            </li>
          </ul>
        </div>
      </section>

      <!-- Anamneses (opt-in) -->
      <section v-if="anamneses.exposed && anamneses.items.length > 0">
        <h3 class="pp-health__section-title">Minhas anamneses</h3>
        <ul class="pp-health__anam-list">
          <li v-for="a in anamneses.items" :key="a.id">
            <router-link :to="{ name: 'anamnesis-detail', params: { id: a.id } }" class="pp-health__anam-item">
              <div class="pp-health__anam-icon"><IconHeart :size="20" /></div>
              <div class="pp-health__anam-body">
                <div class="pp-health__anam-title">{{ a.specialty || 'Anamnese geral' }} · v{{ a.version_number }}</div>
                <div class="pp-health__anam-meta">
                  {{ formatDate(a.finalized_at) }}<span v-if="a.professional"> · {{ a.professional.name }}</span>
                </div>
              </div>
              <IconChevronRight :size="18" />
            </router-link>
          </li>
        </ul>
      </section>

      <BaseCard v-else-if="anamneses.exposed">
        <EmptyState
          title="Sem anamnese registrada"
          description="Quando a clínica registrar sua anamnese (alergias, medicações em uso, histórico), você verá aqui."
        >
          <template #icon><IconHeart :size="28" /></template>
        </EmptyState>
      </BaseCard>

      <!-- Cards clínicos — placeholder Sprint E (default-deny) -->
      <section>
        <h3 class="pp-health__section-title">Em breve</h3>

        <BaseCard title="Plano de tratamento">
          <EmptyState
            title="Sem planos ativos"
            description="Os planos de tratamento aprovados aparecem aqui com progresso e próximas sessões."
          >
            <template #icon><IconSparkle :size="28" /></template>
          </EmptyState>
        </BaseCard>

        <BaseCard title="Evolução clínica">
          <EmptyState
            title="Visualização sob critério da clínica"
            description="A clínica decide quais dados do prontuário ficam visíveis aqui."
          >
            <template #icon><IconHeart :size="28" /></template>
          </EmptyState>
        </BaseCard>
      </section>

      <p class="pp-health__footer">
        Default-deny — visualização clínica detalhada é opt-in pela clínica.
      </p>
    </div>
  </AppShell>
</template>

<script setup>
import { computed, onMounted } from 'vue';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import EmptyState from '../components/EmptyState.vue';
import Badge from '../components/Badge.vue';
import DocumentCard from '../components/DocumentCard.vue';
import IconDocument from '../components/icons/IconDocument.vue';
import IconHeart from '../components/icons/IconHeart.vue';
import IconSparkle from '../components/icons/IconSparkle.vue';
import IconClock from '../components/icons/IconClock.vue';
import IconShield from '../components/icons/IconShield.vue';
import IconChevronRight from '../components/icons/IconChevronRight.vue';
import { useDocumentsStore } from '../store/documents';
import { useAnamnesesStore } from '../store/anamneses';
import { useConsentRecordsStore } from '../store/consent_records';
import { formatDate } from '../utils/format';

const docs      = useDocumentsStore();
const anamneses = useAnamnesesStore();
const consents  = useConsentRecordsStore();

const pendingDocRequests = computed(() => docs.requests.filter(r => r.status === 'pending'));

const TYPE_LABELS = { atestado: 'Atestado', recibo: 'Recibo', receita: 'Receita', outro: 'Documento' };
function labelType(t) { return TYPE_LABELS[t] || t || 'Documento'; }

onMounted(async () => {
  // Disparados em paralelo — Pinia normaliza o estado
  await Promise.all([docs.fetch(), anamneses.fetch(), consents.fetch()]);
  docs.fetchRequests();
});

async function onOpen(doc) {
  try { await docs.download(doc); } catch (e) { window.alert(e.message); }
}
</script>

<style scoped>
.pp-health { padding: 8px 16px 24px; display: flex; flex-direction: column; gap: 24px; }

.pp-health__pending-banner {
  display: flex; align-items: center; gap: 12px;
  padding: 14px; border-radius: 14px;
  background: linear-gradient(135deg, #fffbeb 0%, #fef3c7 100%);
  border: 1px solid #fcd34d;
  text-decoration: none; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease;
}
.pp-health__pending-banner:hover { box-shadow: 0 4px 12px rgba(15,23,42,.06); }
.pp-health__pending-banner:active { transform: scale(0.99); }
.pp-health__pending-icon {
  width: 40px; height: 40px; border-radius: 12px;
  display: flex; align-items: center; justify-content: center;
  background: #fff; color: #92400e; flex-shrink: 0;
}
.pp-health__pending-body { flex: 1; min-width: 0; }
.pp-health__pending-title { font-weight: 700; font-size: 14px; color: #78350f; }
.pp-health__pending-text  { font-size: 12px; color: #92400e; margin-top: 2px; }

.pp-health__section-head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 8px; }
.pp-health__section-title {
  margin: 0 0 8px; font-size: 13px; font-weight: 700;
  color: var(--pp-color-text-muted); text-transform: uppercase; letter-spacing: 0.5px;
}
.pp-health__cta {
  font-size: 13px; font-weight: 600; color: var(--pp-color-primary);
  text-decoration: none;
}
.pp-health__cta-primary {
  background: var(--pp-color-primary); color: #fff; padding: 10px 16px;
  border-radius: 10px; font-size: 13px; font-weight: 600; text-decoration: none;
  display: inline-block;
}

.pp-health__loading { padding: 24px; text-align: center; color: var(--pp-color-text-muted); font-size: 14px; }

.pp-health__doc-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }

.pp-health__pending {
  margin-top: 16px; padding: 12px;
  background: #fef3c7; border: 1px solid #fde68a; border-radius: 14px;
}
.pp-health__pending-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }
.pp-health__pending-item {
  display: flex; gap: 8px; justify-content: space-between; align-items: flex-start;
  background: #fff; border-radius: 10px; padding: 10px;
}
.pp-health__pending-line  { font-size: 13px; font-weight: 600; color: var(--pp-color-text); }
.pp-health__pending-notes { font-size: 12px; color: var(--pp-color-text-muted); margin-top: 2px; }

.pp-health__anam-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }
.pp-health__anam-item {
  display: flex; align-items: center; gap: 12px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  padding: 14px; text-decoration: none; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-health__anam-item:hover  { box-shadow: 0 4px 12px rgba(15,23,42,.06); border-color: var(--pp-color-primary); }
.pp-health__anam-item:active { transform: scale(0.99); }
.pp-health__anam-icon {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  background: #fee2e2; color: #b91c1c;
}
.pp-health__anam-body { flex: 1; min-width: 0; }
.pp-health__anam-title { font-weight: 600; font-size: 14px; color: var(--pp-color-text); }
.pp-health__anam-meta  { font-size: 12px; color: var(--pp-color-text-muted); margin-top: 2px; }

.pp-health__footer { text-align: center; padding: 8px 16px; font-size: 12px; color: var(--pp-color-text-muted); }
</style>
