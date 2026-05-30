<script setup>
import { ref, computed, onMounted } from 'vue';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import Badge from '../components/Badge.vue';
import EmptyState from '../components/EmptyState.vue';
import AppointmentCard from '../components/AppointmentCard.vue';
import IconCalendar from '../components/icons/IconCalendar.vue';
import IconClock from '../components/icons/IconClock.vue';
import { useAppointmentsStore } from '../store/appointments';
import { formatDate, formatTime } from '../utils/format';

const appointments = useAppointmentsStore();
const tab = ref('upcoming');

const tabs = computed(() => [
  { key: 'upcoming', label: 'Futuras', count: appointments.upcomingCount },
  { key: 'past', label: 'Histórico', count: appointments.pastCount },
]);

const currentList = computed(() =>
  tab.value === 'upcoming' ? appointments.upcoming : appointments.past
);
const pendingRequests = computed(() =>
  appointments.requests.filter(r => r.status === 'pending')
);

onMounted(async () => {
  await appointments.fetch();
  // Carrega pedidos pendentes em paralelo — não bloqueia render principal
  appointments.fetchRequests();
});

function formatPreferredDates(arr) {
  if (!arr || arr.length === 0) return 'Sem horário sugerido';
  return arr.map(d => `${formatDate(d)} às ${formatTime(d)}`).join(' · ');
}
</script>

<template>
  <AppShell>
    <PageHeader title="Consultas" subtitle="Acompanhe seus agendamentos">
      <template #action>
        <router-link
          :to="{ name: 'appointment-new' }"
          class="pp-appts__schedule"
        >
          + Agendar
        </router-link>
      </template>
    </PageHeader>

    <div class="pp-appts__tabs">
      <button
        v-for="t in tabs"
        :key="t.key"
        type="button"
        class="pp-appts__tab"
        :class="{ 'pp-appts__tab--active': tab === t.key }"
        @click="tab = t.key"
      >
        {{ t.label }}
        <Badge
          v-if="t.count > 0"
          :variant="tab === t.key ? 'primary' : 'neutral'"
          size="sm"
        >
          {{ t.count }}
        </Badge>
      </button>
    </div>

    <div class="pp-appts__content">
      <div v-if="appointments.loading" class="pp-appts__loading">
        Carregando…
      </div>

      <template v-else>
        <!-- Pedidos pendentes — aparecem no topo só na tab Futuras -->
        <div
          v-if="tab === 'upcoming' && pendingRequests.length > 0"
          class="pp-appts__pending"
        >
          <div class="pp-appts__pending-title">
            <IconClock :size="14" /> Pedidos aguardando confirmação
          </div>
          <ul class="pp-appts__pending-list">
            <li
              v-for="req in pendingRequests"
              :key="req.id"
              class="pp-appts__pending-item"
            >
              <div class="pp-appts__pending-body">
                <div class="pp-appts__pending-line">
                  {{ formatPreferredDates(req.preferred_dates) }}
                </div>
                <div v-if="req.notes" class="pp-appts__pending-notes">
                  {{ req.notes }}
                </div>
              </div>
              <Badge variant="warning" size="sm">Aguardando</Badge>
            </li>
          </ul>
        </div>

        <!-- Lista real -->
        <ul v-if="currentList.length > 0" class="pp-appts__list">
          <li v-for="appt in currentList" :key="appt.id">
            <AppointmentCard :appointment="appt" />
          </li>
        </ul>

        <EmptyState
          v-else-if="tab === 'upcoming'"
          title="Você não tem consultas agendadas"
          description="Toque em Agendar para solicitar um horário com a clínica."
        >
          <template #icon><IconCalendar :size="28" /></template>
          <template #action>
            <router-link
              :to="{ name: 'appointment-new' }"
              class="pp-appts__cta"
            >
              Solicitar agendamento
            </router-link>
          </template>
        </EmptyState>

        <EmptyState
          v-else
          title="Sem histórico ainda"
          description="As consultas que você já fez aparecerão aqui."
        >
          <template #icon><IconClock :size="28" /></template>
        </EmptyState>
      </template>
    </div>
  </AppShell>
</template>

<style scoped>
.pp-appts__schedule {
  background: var(--pp-color-primary);
  color: #fff;
  border: none;
  padding: 8px 14px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: background 120ms ease;
  text-decoration: none;
  display: inline-block;
}
.pp-appts__schedule:hover {
  background: var(--pp-color-primary-hover);
}

.pp-appts__tabs {
  display: flex;
  gap: 4px;
  padding: 0 var(--pp-content-pad-x);
  background: var(--pp-color-bg);
  border-bottom: 1px solid var(--pp-color-border);
}
.pp-appts__tab {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 12px 16px;
  border: none;
  background: transparent;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  color: var(--pp-color-text-muted);
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
  transition:
    color 120ms ease,
    border-color 120ms ease;
}
.pp-appts__tab--active {
  color: var(--pp-color-primary);
  border-bottom-color: var(--pp-color-primary);
}

.pp-appts__content {
  padding: 16px var(--pp-content-pad-x);
}
.pp-appts__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}

.pp-appts__list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
@media (min-width: 1024px) {
  .pp-appts__list {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 14px;
  }
}

.pp-appts__pending {
  margin-bottom: 16px;
  padding: 12px;
  background: #fef3c7;
  border: 1px solid #fde68a;
  border-radius: 14px;
}
.pp-appts__pending-title {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 700;
  color: #92400e;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 8px;
}
.pp-appts__pending-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.pp-appts__pending-item {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  justify-content: space-between;
  background: #fff;
  border-radius: 10px;
  padding: 10px;
}
.pp-appts__pending-body {
  flex: 1;
  min-width: 0;
}
.pp-appts__pending-line {
  font-size: 13px;
  font-weight: 600;
  color: var(--pp-color-text);
}
.pp-appts__pending-notes {
  font-size: 12px;
  color: var(--pp-color-text-muted);
  margin-top: 2px;
}

.pp-appts__cta {
  background: var(--pp-color-primary);
  color: #fff;
  padding: 10px 16px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  text-decoration: none;
  display: inline-block;
}
</style>
