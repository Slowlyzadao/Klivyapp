<template>
  <AppShell>
    <PageHeader title="Solicitar agendamento" back @back="$router.back()" />

    <div class="pp-new-appt">
      <p class="pp-new-appt__intro">
        Sugira até 3 horários e a clínica entra em contato para confirmar.
      </p>

      <!-- Preflight (consent / financeiro / anamnese) -->
      <PreflightBanner v-if="preflight" :checks="preflight.checks" />

      <BaseCard title="Datas sugeridas">
        <div v-for="(slot, i) in slots" :key="i" class="pp-new-appt__slot">
          <input
            type="datetime-local"
            v-model="slots[i]"
            :min="minDateTime"
            class="pp-new-appt__input"
          />
          <button
            v-if="slots.length > 1"
            type="button"
            class="pp-new-appt__remove"
            aria-label="Remover horário"
            @click="removeSlot(i)"
          ><IconClose :size="14" /></button>
        </div>
        <button
          v-if="slots.length < 3"
          type="button"
          class="pp-new-appt__add"
          @click="addSlot"
        >
          + Adicionar outro horário
        </button>
      </BaseCard>

      <BaseCard title="Preferências">
        <label class="pp-new-appt__field">
          <span class="pp-new-appt__label">Período preferido</span>
          <select v-model="form.preferred_period" class="pp-new-appt__select">
            <option value="">Tanto faz</option>
            <option value="morning">Manhã</option>
            <option value="afternoon">Tarde</option>
            <option value="evening">Noite</option>
          </select>
        </label>

        <label class="pp-new-appt__field">
          <span class="pp-new-appt__label">Observações (opcional)</span>
          <textarea
            v-model="form.notes"
            rows="3"
            placeholder="Algo que a clínica deva saber? Ex: preferência de profissional, retorno de tratamento, etc."
            class="pp-new-appt__textarea"
            maxlength="500"
          />
        </label>
      </BaseCard>

      <p v-if="error" class="pp-new-appt__error">{{ error }}</p>

      <BaseButton
        block size="lg"
        :loading="submitting"
        :disabled="!canSubmit"
        @click="onSubmit"
      >
        Enviar pedido
      </BaseButton>

      <p class="pp-new-appt__hint">
        Sua solicitação fica na fila da recepção. Você recebe uma notificação quando
        a clínica confirmar o horário.
      </p>
    </div>
  </AppShell>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseButton from '../components/BaseButton.vue';
import PreflightBanner from '../components/PreflightBanner.vue';
import IconClose from '../components/icons/IconClose.vue';
import { preflightApi } from '../api/preflight';
import { useAppointmentsStore } from '../store/appointments';

const router = useRouter();
const appointments = useAppointmentsStore();

const slots = ref(['']);
const form  = ref({ preferred_period: '', notes: '' });
const preflight  = ref(null);
const submitting = ref(false);
const error      = ref(null);

// Mínimo: amanhã. Min lead time real vem do setting, mas client trava
// inputs em "amanhã às 00:00" como fallback razoável.
const minDateTime = computed(() => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(0, 0, 0, 0);
  return d.toISOString().slice(0, 16);
});

const canSubmit = computed(() => slots.value.some(s => !!s));

onMounted(async () => {
  try {
    preflight.value = await preflightApi.appointment();
  } catch (_) { /* segue sem preflight */ }
});

function addSlot() { if (slots.value.length < 3) slots.value.push(''); }
function removeSlot(i) { slots.value.splice(i, 1); }

async function onSubmit() {
  error.value = null;
  submitting.value = true;

  const payload = {
    preferred_dates:  slots.value.filter(Boolean).map(s => new Date(s).toISOString()),
    preferred_period: form.value.preferred_period || null,
    notes:            form.value.notes || null
  };

  try {
    await appointments.requestAppointment(payload);
    router.replace({ name: 'appointments', query: { requested: '1' } });
  } catch (e) {
    error.value = e.message;
  } finally {
    submitting.value = false;
  }
}
</script>

<style scoped>
.pp-new-appt { padding: 16px; display: flex; flex-direction: column; gap: 16px; }
.pp-new-appt__intro { margin: 0; font-size: 14px; color: var(--pp-color-text-muted); }

.pp-new-appt__slot { display: flex; gap: 8px; align-items: center; margin-bottom: 10px; }
.pp-new-appt__slot:last-of-type { margin-bottom: 0; }
.pp-new-appt__input {
  flex: 1; padding: 10px 12px; border-radius: 10px;
  border: 1px solid var(--pp-color-border); font-size: 14px;
  font-family: inherit;
}
.pp-new-appt__remove {
  flex-shrink: 0; width: 32px; height: 32px;
  display: inline-flex; align-items: center; justify-content: center;
  border-radius: 8px; border: 1px solid var(--pp-color-border);
  background: #fff; cursor: pointer; color: var(--pp-color-text-muted);
}
.pp-new-appt__remove:hover { color: #dc2626; border-color: #fecaca; }
.pp-new-appt__add {
  margin-top: 10px; padding: 8px 12px; border: 1px dashed var(--pp-color-border);
  background: transparent; border-radius: 10px; cursor: pointer;
  color: var(--pp-color-primary); font-size: 13px; font-weight: 600; width: 100%;
}

.pp-new-appt__field { display: flex; flex-direction: column; gap: 6px; margin-bottom: 12px; }
.pp-new-appt__field:last-child { margin-bottom: 0; }
.pp-new-appt__label { font-size: 12px; font-weight: 600; color: var(--pp-color-text-muted); }
.pp-new-appt__select,
.pp-new-appt__textarea {
  width: 100%; padding: 10px 12px; border-radius: 10px;
  border: 1px solid var(--pp-color-border); font-size: 14px;
  font-family: inherit; resize: vertical;
}

.pp-new-appt__error { color: #b91c1c; font-size: 13px; margin: 0; }
.pp-new-appt__hint  { text-align: center; font-size: 12px; color: var(--pp-color-text-muted); margin: 0; }
</style>
