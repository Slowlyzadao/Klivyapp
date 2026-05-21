<template>
  <AppShell>
    <div class="pp-home">
      <!-- Hero card: próxima consulta -->
      <section class="pp-home__hero" v-if="!loading">
        <div class="pp-home__hero-badge">
          <IconSparkle :size="14" />
          <span>Sua clínica · {{ auth.account?.name }}</span>
        </div>

        <template v-if="next">
          <h2 class="pp-home__hero-title">Sua próxima consulta</h2>
          <p class="pp-home__hero-detail">
            <strong>{{ formatLong(next.starts_at) }}</strong>
          </p>
          <p class="pp-home__hero-detail" v-if="next.professional || next.service">
            {{ [next.professional?.name, next.service?.name].filter(Boolean).join(' · ') }}
          </p>
          <!-- Sprint K — CTA prioritário se sala de telemedicina está aberta agora -->
          <router-link
            v-if="canJoinTelemed"
            :to="{ name: 'telemed-room', params: { id: next.id } }"
            class="pp-home__hero-cta pp-home__hero-cta--live"
          >
            🎥 Entrar na consulta agora
          </router-link>
          <router-link v-else :to="{ name: 'appointment-detail', params: { id: next.id } }" class="pp-home__hero-cta">
            Ver detalhes
          </router-link>
        </template>
        <template v-else>
          <h2 class="pp-home__hero-title">Bem-vindo(a) ao Portal</h2>
          <p class="pp-home__hero-detail">
            Aqui você acompanha consultas, documentos, financeiro e fala com a clínica.
          </p>
          <router-link :to="{ name: 'appointment-new' }" class="pp-home__hero-cta">
            Agendar consulta
          </router-link>
        </template>
      </section>

      <!-- Grid de acessos rápidos -->
      <section class="pp-home__section">
        <h3 class="pp-home__section-title">Acessos rápidos</h3>
        <div class="pp-home__quick">
          <router-link
            v-for="q in quickAccess"
            :key="q.to"
            :to="q.to"
            class="pp-home__quick-item"
            :style="{ '--accent': q.color }"
          >
            <div class="pp-home__quick-icon"><component :is="q.icon" :size="22" /></div>
            <div class="pp-home__quick-label">{{ q.label }}</div>
            <div v-if="q.hint" class="pp-home__quick-hint">{{ q.hint }}</div>
          </router-link>
        </div>
      </section>

      <!-- Sprint H — Banner de inadimplência (warn/block) -->
      <OverdueBanner :restriction="overdueRestriction" />

      <!-- Termos clínicos pendentes (em destaque, se houver) -->
      <section v-if="pendingConsents > 0" class="pp-home__section">
        <router-link :to="{ name: 'consent-records' }" class="pp-home__alert pp-home__alert--warn">
          <IconShield :size="20" />
          <div>
            <div class="pp-home__alert-title">{{ pendingConsents }} termo{{ pendingConsents > 1 ? 's' : '' }} pendente{{ pendingConsents > 1 ? 's' : '' }}</div>
            <div class="pp-home__alert-text">Revise e assine para liberar seus procedimentos.</div>
          </div>
          <IconChevronRight :size="18" />
        </router-link>
      </section>

      <!-- Financeiro em destaque se vencido -->
      <section v-if="hasOverdue" class="pp-home__section">
        <router-link :to="{ name: 'financial' }" class="pp-home__alert pp-home__alert--danger">
          <IconWallet :size="20" />
          <div>
            <div class="pp-home__alert-title">{{ formatCurrency(financial?.overdue_amount_cents || 0) }} em parcelas vencidas</div>
            <div class="pp-home__alert-text">Toque para ver detalhes e regularizar.</div>
          </div>
          <IconChevronRight :size="18" />
        </router-link>
      </section>

      <!-- Recall -->
      <section v-if="home?.cards?.recall_due" class="pp-home__section">
        <BaseCard>
          <div class="pp-home__recall">
            <IconHeart :size="32" />
            <div>
              <div class="pp-home__recall-title">Faz tempo desde sua última consulta</div>
              <div class="pp-home__recall-text">Que tal agendar um retorno? Sua clínica está com horários disponíveis.</div>
            </div>
            <div class="pp-home__recall-actions">
              <button type="button" class="pp-home__recall-dismiss" @click="onDismissRecall" :disabled="dismissing">
                Depois
              </button>
              <router-link :to="{ name: 'appointment-new' }" class="pp-home__recall-cta" @click="onScheduleRecall">Agendar</router-link>
            </div>
          </div>
        </BaseCard>
      </section>

      <section class="pp-home__section">
        <h3 class="pp-home__section-title">Resumo</h3>
        <div class="pp-home__stats">
          <router-link :to="{ name: 'financial' }" class="pp-home__stat" :class="{ 'pp-home__stat--danger': hasOverdue }">
            <div class="pp-home__stat-label">Em aberto</div>
            <div class="pp-home__stat-value">{{ formatCurrency(financial?.open_amount_cents || 0) }}</div>
            <div class="pp-home__stat-hint">{{ financial?.open_count || 0 }} parcela{{ (financial?.open_count || 0) !== 1 ? 's' : '' }}</div>
          </router-link>
          <router-link :to="{ name: 'health' }" class="pp-home__stat">
            <div class="pp-home__stat-label">Documentos</div>
            <div class="pp-home__stat-value">{{ home?.cards?.documents_recent?.length || 0 }}</div>
            <div class="pp-home__stat-hint">Recentes</div>
          </router-link>
          <div class="pp-home__stat">
            <div class="pp-home__stat-label">Mensagens</div>
            <div class="pp-home__stat-value">{{ home?.cards?.unread_messages_count || 0 }}</div>
            <div class="pp-home__stat-hint">Sprint E</div>
          </div>
        </div>
      </section>

      <p class="pp-home__footer">
        Portal versão Sprint D · v0.4
      </p>
    </div>
  </AppShell>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAuthStore } from '../store/auth';
import { useNotificationsStore } from '../store/notifications';
import { http } from '../api/http';
import { recallApi } from '../api/recall';
import AppShell from '../components/AppShell.vue';
import BaseCard from '../components/BaseCard.vue';
import IconCalendar from '../components/icons/IconCalendar.vue';
import IconHeart from '../components/icons/IconHeart.vue';
import IconWallet from '../components/icons/IconWallet.vue';
import IconDocument from '../components/icons/IconDocument.vue';
import IconMessage from '../components/icons/IconMessage.vue';
import IconShield from '../components/icons/IconShield.vue';
import IconSparkle from '../components/icons/IconSparkle.vue';
import IconChevronRight from '../components/icons/IconChevronRight.vue';
import OverdueBanner from '../components/OverdueBanner.vue';
import { formatLong, formatCurrency } from '../utils/format';

const auth = useAuthStore();
const notifications = useNotificationsStore();
const home = ref(null);
const loading = ref(true);
const dismissing = ref(false);

const next             = computed(() => home.value?.cards?.next_appointment);
const financial        = computed(() => home.value?.cards?.financial_summary);
const pendingConsents  = computed(() => home.value?.cards?.pending_consents_count || 0);
const hasOverdue       = computed(() => (financial.value?.overdue_amount_cents || 0) > 0);
const overdueRestriction = computed(() => home.value?.cards?.overdue_restriction || {});
const canJoinTelemed = computed(() => !!next.value?.telemedicine?.can_join_now);

const quickAccess = [
  { to: '/appointments',     label: 'Consultas',    icon: IconCalendar, color: '#2563eb' },
  { to: '/health',           label: 'Saúde',        icon: IconHeart,    color: '#ef4444' },
  { to: '/financial',        label: 'Financeiro',   icon: IconWallet,   color: '#10b981' },
  { to: '/health',           label: 'Documentos',   icon: IconDocument, color: '#f59e0b' },
  { to: '/consent-records',  label: 'Termos',       icon: IconShield,   color: '#06b6d4' },
  { to: '/more',             label: 'Mais',         icon: IconMessage,  color: '#8b5cf6' }
];

onMounted(async () => {
  try {
    home.value = await http.get('/api/v1/patient_portal/home');
  } catch (_) { /* mantém vazio */ }
  finally { loading.value = false; }

  notifications.fetch(); // fire-and-forget
});

async function onDismissRecall() {
  dismissing.value = true;
  try {
    await recallApi.dismiss();
    if (home.value?.cards) home.value.cards.recall_due = false;
  } catch (_) { /* silencia — não-crítico */ }
  finally { dismissing.value = false; }
}

function onScheduleRecall() {
  // Fire-and-forget — apenas registra a intenção pra métrica
  recallApi.scheduleIntent().catch(() => {});
}
</script>

<style scoped>
.pp-home { padding: 4px 16px 32px; }

/* Hero */
.pp-home__hero {
  margin: 8px 0 24px;
  padding: 24px;
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 50%, #4338ca 100%);
  color: #fff;
  border-radius: 22px;
  box-shadow: 0 16px 32px -16px rgba(37, 99, 235, .55);
  position: relative; overflow: hidden;
}
.pp-home__hero::before {
  content: ''; position: absolute; inset: 0;
  background: radial-gradient(ellipse at top right, rgba(255,255,255,.18), transparent 60%);
  pointer-events: none;
}
.pp-home__hero-badge {
  display: inline-flex; align-items: center; gap: 6px;
  font-size: 12px; font-weight: 600; padding: 6px 10px;
  background: rgba(255,255,255,.18); border-radius: 999px;
  backdrop-filter: blur(6px);
  position: relative;
}
.pp-home__hero-title  { margin: 12px 0 6px; font-size: 22px; font-weight: 700; position: relative; }
.pp-home__hero-detail { margin: 0 0 4px; font-size: 14px; line-height: 1.5; opacity: .92; position: relative; text-transform: capitalize; }
.pp-home__hero-detail:not(:first-of-type) { text-transform: none; }
.pp-home__hero-cta {
  position: relative; display: inline-block; margin-top: 14px;
  background: rgba(255,255,255,.95); color: var(--pp-color-primary);
  padding: 8px 16px; border-radius: 999px;
  font-size: 13px; font-weight: 700; text-decoration: none;
}
.pp-home__hero-cta:hover { background: #fff; }
.pp-home__hero-cta--live {
  background: #16a34a; color: #fff;
  padding: 12px 22px; font-size: 15px;
  box-shadow: 0 4px 14px rgba(22, 163, 74, .4);
  animation: pulse 2s ease-in-out infinite;
}
.pp-home__hero-cta--live:hover { background: #15803d; }
@keyframes pulse {
  0%, 100% { box-shadow: 0 4px 14px rgba(22, 163, 74, .4); }
  50%      { box-shadow: 0 4px 24px rgba(22, 163, 74, .7); }
}

/* Section */
.pp-home__section { margin-bottom: 28px; }
.pp-home__section-title {
  margin: 0 0 12px; font-size: 13px; font-weight: 700;
  color: var(--pp-color-text-muted); text-transform: uppercase; letter-spacing: 0.5px;
}

/* Quick grid */
.pp-home__quick { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
.pp-home__quick-item {
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  padding: 16px 10px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 16px;
  text-decoration: none; color: var(--pp-color-text);
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-home__quick-item:hover  { box-shadow: 0 4px 12px rgba(15,23,42,.06); border-color: var(--accent); }
.pp-home__quick-item:active { transform: scale(0.97); }
.pp-home__quick-icon {
  width: 44px; height: 44px; border-radius: 12px;
  display: flex; align-items: center; justify-content: center;
  background: color-mix(in srgb, var(--accent) 12%, transparent);
  color: var(--accent);
}
.pp-home__quick-label { font-size: 13px; font-weight: 600; }
.pp-home__quick-hint  { font-size: 11px; color: var(--pp-color-text-muted); }

/* Alerts (consent pending / overdue financial) */
.pp-home__alert {
  display: flex; align-items: center; gap: 12px;
  padding: 14px; border-radius: 14px;
  text-decoration: none; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease;
}
.pp-home__alert:hover  { box-shadow: 0 4px 12px rgba(15,23,42,.06); }
.pp-home__alert:active { transform: scale(0.99); }
.pp-home__alert--warn  { background: linear-gradient(135deg, #fffbeb 0%, #fef3c7 100%); border: 1px solid #fcd34d; color: #78350f; }
.pp-home__alert--danger { background: linear-gradient(135deg, #fef2f2 0%, #fee2e2 100%); border: 1px solid #fca5a5; color: #7f1d1d; }
.pp-home__alert > svg:first-child { flex-shrink: 0; }
.pp-home__alert > div { flex: 1; min-width: 0; }
.pp-home__alert-title { font-weight: 700; font-size: 14px; }
.pp-home__alert-text  { font-size: 12px; opacity: .85; margin-top: 2px; }

/* Recall card */
.pp-home__recall { display: flex; align-items: center; gap: 12px; }
.pp-home__recall > svg:first-child { color: #ef4444; flex-shrink: 0; }
.pp-home__recall > div:nth-child(2) { flex: 1; min-width: 0; }
.pp-home__recall-title { font-weight: 700; font-size: 15px; color: var(--pp-color-text); }
.pp-home__recall-text  { font-size: 13px; color: var(--pp-color-text-muted); margin-top: 2px; }
.pp-home__recall-actions { display: flex; gap: 8px; flex-shrink: 0; }
.pp-home__recall-dismiss {
  background: transparent; border: 1px solid var(--pp-color-border);
  color: var(--pp-color-text-muted); padding: 8px 12px;
  border-radius: 10px; font-size: 13px; font-weight: 600; cursor: pointer;
  white-space: nowrap;
}
.pp-home__recall-dismiss:hover:not(:disabled) { background: #f1f5f9; }
.pp-home__recall-dismiss:disabled { opacity: 0.5; cursor: not-allowed; }
.pp-home__recall-cta {
  background: var(--pp-color-primary); color: #fff; padding: 10px 14px;
  border-radius: 10px; font-size: 13px; font-weight: 600; text-decoration: none;
  white-space: nowrap;
}

/* Stats */
.pp-home__stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
.pp-home__stat {
  background: #fff; border: 1px solid var(--pp-color-border);
  border-radius: 14px; padding: 14px 12px;
  text-decoration: none; color: inherit;
  transition: border-color 120ms ease;
}
.pp-home__stat:hover { border-color: var(--pp-color-primary); }
.pp-home__stat--danger { border-color: #fca5a5; background: #fef2f2; }
.pp-home__stat-label { font-size: 11px; color: var(--pp-color-text-muted); font-weight: 600; text-transform: uppercase; }
.pp-home__stat-value { font-size: 18px; font-weight: 700; color: var(--pp-color-text); margin-top: 4px; }
.pp-home__stat-hint  { font-size: 10px; color: var(--pp-color-text-muted); margin-top: 2px; }

.pp-home__footer {
  margin-top: 12px; text-align: center; font-size: 11px; color: var(--pp-color-text-muted);
}
</style>
