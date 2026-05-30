<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseButton from '../components/BaseButton.vue';
import EmptyState from '../components/EmptyState.vue';
import AppointmentStatusBadge from '../components/AppointmentStatusBadge.vue';
import TelemedicineJoinCard from '@plugins/telemed/frontend/patient/components/TelemedicineJoinCard.vue';
import IconCalendar from '../components/icons/IconCalendar.vue';
import IconCheck from '../components/icons/IconCheck.vue';
import IconClose from '../components/icons/IconClose.vue';
import { appointmentsApi } from '../api/appointments';
import { useAppointmentsStore } from '../store/appointments';
import { formatLong, formatTime, formatRelative } from '../utils/format';

const route = useRoute();
const router = useRouter();
const store = useAppointmentsStore();

const appointment = ref(null);
const loading = ref(true);
const confirming = ref(false);
const cancelling = ref(false);

const formattedWhen = computed(() => formatLong(appointment.value?.starts_at));
const upcoming = computed(
  () =>
    appointment.value &&
    !appointment.value.cancelled &&
    new Date(appointment.value.starts_at) > new Date()
);

onMounted(async () => {
  try {
    appointment.value = await appointmentsApi.get(route.params.id);
  } catch (_) {
    /* fica null → EmptyState */
  } finally {
    loading.value = false;
  }
});

async function onConfirm() {
  confirming.value = true;
  try {
    const updated = await store.confirm(appointment.value.id);
    appointment.value = { ...appointment.value, ...updated };
  } catch (e) {
    window.alert(e.message);
  } finally {
    confirming.value = false;
  }
}

async function onCancel() {
  const reason = window.prompt('Quer nos contar o motivo? (opcional)');
  if (reason === null) return; // usuário desistiu

  cancelling.value = true;
  try {
    const updated = await store.cancel(appointment.value.id, reason);
    appointment.value = { ...appointment.value, ...updated };
  } catch (e) {
    window.alert(e.message);
  } finally {
    cancelling.value = false;
  }
}
</script>

<template>
  <AppShell>
    <PageHeader title="Consulta" back @back="$router.back()" />

    <div v-if="loading" class="pp-appt-detail__loading">Carregando…</div>

    <div v-else-if="appointment" class="pp-appt-detail">
      <!-- Hero da consulta -->
      <section class="pp-appt-detail__hero">
        <AppointmentStatusBadge
          :status="appointment.status"
          :cancelled="appointment.cancelled"
        />
        <h2 class="pp-appt-detail__title">{{ appointment.title }}</h2>
        <div class="pp-appt-detail__when">
          <IconCalendar :size="16" /> {{ formattedWhen }}
        </div>
      </section>

      <!-- Detalhes -->
      <BaseCard>
        <div v-if="appointment.professional" class="pp-appt-detail__row">
          <span class="pp-appt-detail__label">Profissional</span>
          <span class="pp-appt-detail__value">{{
            appointment.professional.name
          }}</span>
        </div>
        <div v-if="appointment.service" class="pp-appt-detail__row">
          <span class="pp-appt-detail__label">Serviço</span>
          <span class="pp-appt-detail__value">{{
            appointment.service.name
          }}</span>
        </div>
        <div class="pp-appt-detail__row">
          <span class="pp-appt-detail__label">Horário</span>
          <span class="pp-appt-detail__value"
            >{{ formatTime(appointment.starts_at) }} —
            {{ formatTime(appointment.ends_at) }}</span
          >
        </div>
        <div v-if="appointment.description" class="pp-appt-detail__row">
          <span class="pp-appt-detail__label">Observações</span>
          <span class="pp-appt-detail__value">{{
            appointment.description
          }}</span>
        </div>
      </BaseCard>

      <!-- Sprint J — Telemedicina -->
      <TelemedicineJoinCard :telemedicine="appointment.telemedicine" />

      <!-- Ações -->
      <div
        v-if="appointment.can_confirm || appointment.can_cancel"
        class="pp-appt-detail__actions"
      >
        <BaseButton
          v-if="appointment.can_confirm"
          :loading="confirming"
          @click="onConfirm"
        >
          <IconCheck :size="16" /> Confirmar presença
        </BaseButton>
        <BaseButton
          v-if="appointment.can_cancel"
          variant="ghost-danger"
          :loading="cancelling"
          @click="onCancel"
        >
          <IconClose :size="16" /> Cancelar consulta
        </BaseButton>
      </div>

      <p v-if="appointment.cancelled" class="pp-appt-detail__cancelled-msg">
        Esta consulta foi cancelada
        {{ formatRelative(appointment.cancelled_at) }}.
      </p>

      <p
        v-else-if="
          !appointment.can_cancel && !appointment.can_confirm && upcoming
        "
        class="pp-appt-detail__notice"
      >
        Cancelamento online não disponível. Para alterar, entre em contato com a
        clínica.
      </p>
    </div>

    <EmptyState
      v-else
      title="Consulta não encontrada"
      description="Esta consulta pode ter sido removida ou você não tem acesso a ela."
    >
      <template #icon><IconCalendar :size="28" /></template>
      <template #action>
        <BaseButton @click="$router.push({ name: 'appointments' })">
          Voltar
        </BaseButton>
      </template>
    </EmptyState>
  </AppShell>
</template>

<style scoped>
.pp-appt-detail {
  padding: 16px var(--pp-content-pad-x);
  display: flex;
  flex-direction: column;
  gap: 16px;
}
@media (min-width: 1024px) {
  .pp-appt-detail {
    max-width: 760px;
  }
  .pp-appt-detail__hero {
    padding: 28px;
  }
  .pp-appt-detail__title {
    font-size: 26px;
  }
  .pp-appt-detail__actions {
    flex-direction: row;
  }
  .pp-appt-detail__actions :deep(button) {
    flex: 1;
  }
}
.pp-appt-detail__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}

.pp-appt-detail__hero {
  padding: 20px;
  border-radius: 16px;
  color: #fff;
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 50%, #4338ca 100%);
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.pp-appt-detail__hero :deep(.pp-badge) {
  align-self: flex-start;
  background: rgba(255, 255, 255, 0.18);
  color: #fff;
  border-color: rgba(255, 255, 255, 0.25);
}
.pp-appt-detail__title {
  margin: 4px 0 0;
  font-size: 22px;
  font-weight: 700;
}
.pp-appt-detail__when {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  opacity: 0.92;
  font-size: 14px;
  text-transform: capitalize;
}

.pp-appt-detail__row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--pp-color-border);
  font-size: 14px;
}
.pp-appt-detail__row:last-child {
  border-bottom: none;
}
.pp-appt-detail__label {
  color: var(--pp-color-text-muted);
  flex-shrink: 0;
}
.pp-appt-detail__value {
  color: var(--pp-color-text);
  font-weight: 600;
  text-align: right;
}

.pp-appt-detail__actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.pp-appt-detail__cancelled-msg,
.pp-appt-detail__notice {
  text-align: center;
  font-size: 13px;
  color: var(--pp-color-text-muted);
  padding: 8px 0;
}
</style>
