<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  plan: { type: Object, default: null },
  profName: { type: String, default: '—' },
  profAvatar: { type: String, default: '' },
  // Label + slug já resolvidos pelo composable (espelha "Atribuir Função"
  // em /settings/agents/list: usa klivy_role.name quando existe, senão
  // "Administrador"/"Profissional"). Não recebe role bruto pra evitar que
  // a UI mostre "PROFISSIONAL" pra todo mundo.
  profRoleLabel: { type: String, default: '' },
  profRoleSlug: { type: String, default: '' },
});

defineEmits(['view-plans', 'change-responsible']);

// "Não atribuído" / "—" indicam ausência real de responsável (paciente sem
// `responsible_professional_id` no banco — comum em pacientes importados
// do Clinicorp). Render usa estado vazio em vez de avatar genérico pra
// evitar parecer que tem profissional quando não tem.
const hasResponsible = computed(
  () => props.profName && !['—', 'Não atribuído'].includes(props.profName)
);

// Smart default pro título do plano. Em vez do hardcoded "Plano sem título",
// gera fallback informativo baseado na data de criação ou id. Útil porque
// `TreatmentPlan.title` é opcional e muitos planos ficam sem título no MVP.
const planTitle = computed(() => {
  if (props.plan?.title?.trim()) return props.plan.title;
  if (props.plan?.created_at) {
    const d = new Date(props.plan.created_at);
    if (!Number.isNaN(d.getTime())) {
      const dt = d.toLocaleDateString('pt-BR');
      return `Plano de tratamento · ${dt}`;
    }
  }
  if (props.plan?.id) return `Plano de tratamento #${props.plan.id}`;
  return 'Plano de tratamento';
});
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-blue">
          <i class="i-lucide-stethoscope w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">Tratamento Ativo</span>
          <span class="reg-section-subtitle"
            >Plano e profissional responsável</span
          >
        </div>
      </div>
      <BeclinicButton
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-arrow-right"
        trailing-icon
        label="Ver Planos"
        @click="$emit('view-plans')"
      />
    </div>
    <div class="reg-section-body">
      <div v-if="plan">
        <p class="geral-plan-title">
          {{ planTitle }}
        </p>
        <div class="flex items-center gap-2 mt-2">
          <span
            class="status-badge"
            :class="
              plan.status === 'in_progress' ? 'badge-blue' : 'badge-green'
            "
          >
            {{
              plan.status === 'in_progress'
                ? 'Em andamento'
                : plan.status === 'approved'
                  ? 'Aprovado'
                  : plan.status
            }}
          </span>
          <span
            v-if="plan.estimated_duration"
            class="text-slate-500 text-xs"
          >
            {{ plan.estimated_duration }}
          </span>
        </div>
        <p
          v-if="plan.description"
          class="text-slate-400 text-xs mt-2 line-clamp-2"
        >
          {{ plan.description }}
        </p>
      </div>
      <p v-else class="text-sm text-slate-500">Nenhum plano ativo.</p>

      <div class="geral-divider" />

      <div class="geral-prof-card">
        <div class="geral-prof-header">
          <span class="geral-prof-label">Profissional Responsável</span>
          <div class="geral-prof-header-actions">
            <Tooltip
              label="Quem cuida regularmente deste paciente. Atribuído automaticamente na primeira ação (agendar, criar plano, atender, cobrar) e fica fixo. Outras consultas isoladas com profissionais diferentes não alteram esse campo — só troca manual."
              position="left"
              multiline
            >
              <i class="i-lucide-info geral-prof-help-icon" />
            </Tooltip>
            <button
              type="button"
              class="geral-prof-change-btn"
              @click="$emit('change-responsible')"
            >
              <i class="i-lucide-user-cog w-3.5 h-3.5" />
              Trocar
            </button>
          </div>
        </div>

        <!-- Estado normal: paciente tem profissional atribuído -->
        <div v-if="hasResponsible" class="geral-prof-row">
          <Avatar
            :src="profAvatar"
            :name="profName"
            :size="40"
            rounded-full
          />
          <div class="geral-prof-info">
            <p class="geral-prof-name">{{ profName }}</p>
            <span
              v-if="profRoleLabel"
              class="geral-prof-badge"
              :class="profRoleSlug ? `geral-prof-badge--${profRoleSlug}` : ''"
            >
              <i class="i-lucide-shield-check w-3 h-3" />
              {{ profRoleLabel }}
            </span>
          </div>
        </div>

        <!-- Estado vazio: sem profissional atribuído (típico de pacientes
             importados do Clinicorp). Visual neutro pra não confundir. -->
        <div v-else class="geral-prof-empty">
          <div class="geral-prof-empty-icon">
            <i class="i-lucide-user-x w-5 h-5" />
          </div>
          <div class="geral-prof-empty-text">
            <p class="geral-prof-empty-title">Sem profissional atribuído</p>
            <p class="geral-prof-empty-hint">
              Defina ao agendar uma consulta ou criar um plano de tratamento.
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
