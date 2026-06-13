<script setup>
import { ref, onMounted, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import AgendaAgentServicesAPI from '@plugins/agenda/frontend/api/agendaAgentServices';

// Campo "Serviços que atende" do modal Editar Agente. Chips clicáveis com
// auto-save: cada toque grava o conjunto inteiro no backend (otimista, com
// reversão em caso de erro). Só os serviços marcados ficam agendáveis —
// inclusive pela Bia.
const props = defineProps({
  agentId: { type: Number, required: true },
});

const services = ref([]);
const selected = ref(new Set());
const loading = ref(true);
const saving = ref(false);

onMounted(async () => {
  try {
    const { data } = await AgendaAgentServicesAPI.getForAgent(props.agentId);
    services.value = data.services || [];
    selected.value = new Set(data.selected_ids || []);
  } catch (error) {
    // silencioso — campo é complementar, não trava o modal
  } finally {
    loading.value = false;
  }
});

const hasServices = computed(() => services.value.length > 0);
const isSelected = id => selected.value.has(id);

const toggle = async service => {
  const previous = new Set(selected.value);
  const next = new Set(selected.value);
  if (next.has(service.id)) {
    next.delete(service.id);
  } else {
    next.add(service.id);
  }
  selected.value = next;

  saving.value = true;
  try {
    await AgendaAgentServicesAPI.setForAgent(props.agentId, [...next]);
  } catch (error) {
    selected.value = previous; // reverte
    useAlert('Não foi possível salvar os serviços.');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="w-full mt-3 mb-4">
    <div class="rounded-md border border-n-weak bg-n-slate-2 px-3 py-3">
      <div class="flex items-center gap-2">
        <span class="i-lucide-stethoscope text-n-slate-11 shrink-0" />
        <span class="text-body-medium text-n-slate-12">Serviços que atende</span>
        <span
          v-if="saving"
          class="i-lucide-loader-circle animate-spin text-n-slate-10 ltr:ml-auto rtl:mr-auto"
        />
      </div>
      <p class="text-body-small text-n-slate-11 mt-1 mb-3">
        Marque os serviços que este profissional realiza. Só os marcados ficam
        disponíveis para agendamento (inclusive pela Bia).
      </p>

      <div v-if="loading" class="text-body-small text-n-slate-10">
        Carregando serviços…
      </div>
      <div v-else-if="!hasServices" class="text-body-small text-n-slate-10">
        Nenhum serviço cadastrado na agenda ainda.
      </div>
      <div v-else class="flex flex-wrap gap-2">
        <button
          v-for="service in services"
          :key="service.id"
          type="button"
          class="px-3 py-1.5 rounded-full text-sm font-medium border transition-all duration-100 active:scale-[0.97]"
          :class="
            isSelected(service.id)
              ? 'bg-woot-500 text-white border-woot-500'
              : 'bg-n-slate-1 text-n-slate-11 border-n-weak hover:border-woot-500 hover:text-n-slate-12'
          "
          @click="toggle(service)"
        >
          {{ service.name }}
        </button>
      </div>
    </div>
  </div>
</template>
