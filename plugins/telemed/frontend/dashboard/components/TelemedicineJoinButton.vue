<script setup>
// Botão "Entrar na sala" reutilizável (Sprint K).
//
// Renderiza UM dos dois estados:
//   - habilitado → user é o responsável + evento é teleconsulta + não cancelado
//   - escondido  → user NÃO é o responsável OU evento não é teleconsulta
//
// 2026-05-19 (Google Meet pattern): o DOUTOR entra a qualquer hora. Não
// há mais "janela de entrada" do lado dele — só bloqueia se a consulta
// foi cancelada / status final. Antes, o botão ficava disabled fora da
// janela 10-30min; agora fica sempre live, e o doutor pode entrar pra
// testar conexão, atrasar o paciente, etc.
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useTelemedicineJoin } from '../composables/useTelemedicineJoin';

const props = defineProps({
  event: { type: Object, required: true },
});

const store = useStore();
const { joining, join } = useTelemedicineJoin();

const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const isTelemedicine = computed(
  () => props.event?.custom_attributes?.telemedicine_enabled === true
);

const isResponsible = computed(
  () => currentUserId.value && props.event?.user_id === currentUserId.value
);

// Estados que tornam a consulta inelegível pra teleconsulta — espelha o
// backend (`PERMANENT_REASONS` em TelemedicineSession). Aqui só usamos pro
// tooltip e disable. O backend é a fonte da verdade — se o front mostrar
// indevidamente, o endpoint recusa com 422.
const finalStatuses = ['completed', 'cancelled', 'no_show'];

const blockingReason = computed(() => {
  if (props.event?.cancelled) return 'cancelado';
  if (finalStatuses.includes(props.event?.status)) return 'status_final';
  if (!props.event?.starts_at || !props.event?.ends_at) return 'sem_horario';
  return null;
});

const visible = computed(() => isTelemedicine.value && isResponsible.value);
const enabled = computed(() => !blockingReason.value);

const tooltip = computed(() => {
  if (enabled.value) return 'Entrar agora na sala da teleconsulta';
  if (blockingReason.value === 'cancelado') return 'Consulta cancelada.';
  if (blockingReason.value === 'status_final') return 'Consulta já encerrada.';
  if (blockingReason.value === 'sem_horario')
    return 'Agendamento sem horário definido.';
  return 'Sala indisponível';
});

async function handleClick() {
  if (!enabled.value || joining.value) return;
  await join(props.event);
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<!-- Strings em PT-BR hardcoded propositais (tooltip + label do botão são UX
     dinâmica deste MVP). Pendente i18n. -->
<template>
  <button
    v-if="visible"
    type="button"
    :disabled="!enabled || joining"
    :title="tooltip"
    class="telemed-join-btn"
    :class="{ 'telemed-join-btn--disabled': !enabled }"
    @click="handleClick"
  >
    <i
      :class="joining ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-video'"
      class="size-4"
    />
    <span>{{ joining ? 'Conectando...' : 'Entrar na sala' }}</span>
  </button>
</template>

<style scoped>
.telemed-join-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 40px;
  padding: 0 14px;
  background: #16a34a;
  color: #fff;
  border: 0;
  border-radius: 0.5rem;
  font-size: 13px;
  font-weight: 700;
  cursor: pointer;
  box-shadow: 0 1px 3px rgba(22, 163, 74, 0.25);
  transition:
    background 120ms ease,
    transform 80ms ease;
}
.telemed-join-btn:hover:not(:disabled) {
  background: #15803d;
}
.telemed-join-btn:active:not(:disabled) {
  transform: scale(0.97);
}
.telemed-join-btn--disabled,
.telemed-join-btn:disabled {
  background: #475569;
  color: #cbd5e1;
  cursor: not-allowed;
  box-shadow: none;
}
</style>
