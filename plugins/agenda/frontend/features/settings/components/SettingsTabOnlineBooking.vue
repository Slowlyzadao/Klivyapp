<template>
  <div class="notif-root">
    <!-- Header -->
    <div class="notif-header flex items-center justify-between mb-6">
      <div>
        <h2 class="section-title mb-1">Agendamento Online Público</h2>
        <p class="section-sub-title">
          Configure como os seus pacientes podem agendar consultas diretamente
          pela web.
        </p>
      </div>
      <button
        class="save-btn"
        :class="{ saving: onlineSaving }"
        @click="saveOnlineConfig"
      >
        <i
          v-if="onlineSaving"
          class="i-lucide-loader-circle animate-spin size-[15px]"
        />
        <i v-else class="i-lucide-save size-[15px]" />
        <span>{{
          onlineSaving ? 'Salvando...' : 'Salvar configurações'
        }}</span>
      </button>
    </div>

    <div v-if="onlineConfigLoading" class="notif-empty">
      <i class="i-lucide-loader-circle animate-spin notif-empty-ico" />
      <p class="notif-empty-title">Carregando configurações...</p>
    </div>

    <div v-else class="online-grid">
      <!-- Coluna Esquerda: Link e Regras -->
      <div class="online-col">
        <!-- Card do Link -->
        <div class="online-card">
          <h3 class="online-card-title">Link público de agendamento</h3>
          <p class="online-card-sub">
            Compartilhe este link em redes sociais (Instagram, WhatsApp) para
            receber agendamentos.
          </p>

          <!-- Seletor de agente (apenas para admins) -->
          <div
            v-if="isAdmin && agents.length > 0"
            class="agent-selector-wrap"
          >
            <label class="agent-selector-label">
              <i class="i-lucide-user-round size-[13px]" />
              Visualizando link do profissional:
            </label>
            <ModernSelect
              v-model="selectedAgentId"
              :options="agentOptions"
              class="agent-selector-select"
            />
          </div>

          <div class="link-input-group">
            <div class="link-readonly">
              <i class="i-lucide-link-2 link-ico" />
              <span class="link-text">{{ publicUrl }}</span>
            </div>
            <button class="copy-btn" @click="copyPublicUrl">
              <i class="i-lucide-copy size-[14px]" />
              <span>Copiar</span>
            </button>
          </div>
          <p class="link-hint">
            <span v-if="isAdmin && selectedAgentId">
              Exibindo link de
              <strong>{{ selectedAgent.name }}</strong>
            </span>
            <span v-else>
              O link acima é exclusivo para o seu perfil:
              <strong>{{ currentUser.name }}</strong>
            </span>
          </p>
        </div>

        <!-- Card de Regras -->
        <div class="online-card">
          <h3 class="online-card-title">Regras de agendamento</h3>
          <div class="rules-list">
            <div class="rule-toggle-item">
              <div class="rule-info">
                <span class="rule-label">Ativar agendamento online</span>
                <span class="rule-sub"
                  >Permitir que pacientes vejam sua agenda e marquem
                  horários</span
                >
              </div>
              <button
                class="toggle-switch"
                :class="{ 'toggle-on': onlineConfig.enabled }"
                @click="onlineConfig.enabled = !onlineConfig.enabled"
              >
                <span class="toggle-thumb" />
              </button>
            </div>

            <div class="rule-toggle-item">
              <div class="rule-info">
                <span class="rule-label">Permitir novos pacientes</span>
                <span class="rule-sub"
                  >Se desativado, apenas pacientes já cadastrados poderão
                  agendar</span
                >
              </div>
              <button
                class="toggle-switch"
                :class="{ 'toggle-on': onlineConfig.allow_new_patients }"
                @click="
                  onlineConfig.allow_new_patients =
                    !onlineConfig.allow_new_patients
                "
              >
                <span class="toggle-thumb" />
              </button>
            </div>

            <div class="rule-row-item">
              <div class="rule-info">
                <span class="rule-label">Antecedência mínima</span>
                <span class="rule-sub"
                  >Tempo mínimo antes da consulta para permitir o
                  agendamento</span
                >
              </div>
              <div class="rule-input-wrap">
                <input
                  v-model.number="onlineConfig.min_lead_time_minutes"
                  type="number"
                  class="rule-num-input"
                />
                <span class="rule-unit">minutos</span>
              </div>
            </div>

            <div class="rule-row-item">
              <div class="rule-info">
                <span class="rule-label">Limite futuro de agendamento</span>
                <span class="rule-sub"
                  >Até quantos dias à frente o paciente pode ver sua
                  agenda</span
                >
              </div>
              <div class="rule-input-wrap">
                <input
                  v-model.number="onlineConfig.future_limit_days"
                  type="number"
                  class="rule-num-input"
                />
                <span class="rule-unit">dias</span>
              </div>
            </div>

            <div class="rule-row-item">
              <div class="rule-info">
                <span class="rule-label">{{ $t('AGENDA.SLOT_INTERVAL.LABEL') }}</span>
                <span class="rule-sub"
                  >{{ $t('AGENDA.SLOT_INTERVAL.DESCRIPTION') }}</span
                >
              </div>
              <div class="rule-input-wrap">
                <ModernSelect
                  v-model.number="agendaSettingsData.slot_interval_minutes"
                  :options="[
                    { value: 15, label: $t('AGENDA.SLOT_INTERVAL.OPTIONS.15') },
                    { value: 30, label: $t('AGENDA.SLOT_INTERVAL.OPTIONS.30') },
                    { value: 60, label: $t('AGENDA.SLOT_INTERVAL.OPTIONS.60') }
                  ]"
                  class="rule-num-input"
                  style="min-width: 140px;"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Coluna Direita: Campos do Formulário -->
      <div class="online-col">
        <div class="online-card">
          <div class="flex justify-between items-center mb-2">
            <h3 class="online-card-title mb-0">Campos do formulário</h3>
            <span class="nc-badge nc-badge-type">Padrão Beclinic</span>
          </div>
          <p class="online-card-sub text-sm">
            Estes são os campos que o paciente preencherá ao solicitar o
            agendamento.
          </p>

          <div class="fields-list">
            <div
              v-for="field in onlineConfig.form_fields"
              :key="field.id"
              class="field-item"
            >
              <div class="field-drag">
                <i class="i-lucide-grip-vertical size-[14px] opacity-30" />
              </div>
              <div class="field-main">
                <span class="field-label-text">{{ field.label }}</span>
                <span class="field-type-tag">{{ field.type }}</span>
              </div>
              <div class="field-actions">
                <span
v-if="field.required" class="field-req-badge"
                  >Obrigatório</span
                >
                <i
                  v-if="field.system"
                  class="i-lucide-lock size-[12px] opacity-40 ml-2"
                  title="Campo do sistema"
                />
              </div>
            </div>
          </div>

          <div class="mt-4 p-3 rounded-lg info-note-box">
            <p class="text-sm text-slate-700 leading-relaxed italic">
              <i
                class="i-lucide-info size-[12px] inline-block mr-1 translate-y-[-1px]"
              />
              Campos do sistema são obrigatórios para a criação do contato.
              Campos personalizados serão suportados na versão 1.1.
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted } from 'vue';
import { useSettingsOnlineBooking } from '../composables/useSettingsOnlineBooking';
import ModernSelect from '../../../components/ModernSelect.vue';

const props = defineProps({
  accountId: {
    type: [String, Number],
    required: true
  },
  currentUser: {
    type: Object,
    required: true
  },
  isAdmin: {
    type: Boolean,
    default: false
  },
  agents: {
    type: Array,
    default: () => []
  },
  agendaSettingsData: {
    type: Object,
    required: true
  }
});

const emit = defineEmits(['persist-settings']);

const {
  onlineConfig,
  onlineConfigLoading,
  onlineSaving,
  selectedAgentId,
  selectedAgent,
  publicUrl,
  fetchOnlineConfig,
  saveOnlineConfig,
  copyPublicUrl
} = useSettingsOnlineBooking(props, emit);

const agentOptions = computed(() => {
  const opts = [{ value: null, label: `${props.currentUser?.name} (você)` }];
  if (props.agents && props.agents.length) {
    props.agents.forEach(a => {
      if (a.id !== props.currentUser?.id) {
        opts.push({ value: a.id, label: a.name });
      }
    });
  }
  return opts;
});

onMounted(() => {
  fetchOnlineConfig();
});
</script>

<style scoped>
/* ─── AGENDAMENTO ONLINE ─────────────────────────────────────────── */
.online-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  padding: 0 0 40px;
}
.online-col {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.online-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 20px;
}
.online-card-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0 0 6px;
}
.online-card-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0 0 16px;
  line-height: 1.5;
}
/* Link público */
.link-input-group {
  display: flex;
  gap: 8px;
  align-items: center;
}
.link-readonly {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 8px 12px;
  overflow: hidden;
}
.link-ico {
  width: 14px;
  height: 14px;
  opacity: 0.5;
  flex-shrink: 0;
}
.link-text {
  @apply text-sm;
  color: rgb(var(--slate-11));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.copy-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  background: rgb(var(--blue-9));
  color: #fff;
  border: none;
  border-radius: 8px;
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: background 0.15s;
}
.copy-btn:hover {
  background: rgb(var(--blue-10));
}
.link-hint {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 8px 0 0;
}
/* Regras */
.rules-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rule-toggle-item,
.rule-row-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.rule-toggle-item:last-child,
.rule-row-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}
.rule-info {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.rule-label {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}
.rule-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  line-height: 1.4;
}
.rule-input-wrap {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}
.rule-num-input {
  width: 70px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  padding: 6px 8px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  text-align: center;
}
.rule-num-input:focus {
  outline: none;
  border-color: rgb(var(--blue-8));
}
.rule-unit {
  @apply text-sm;
  color: rgb(var(--slate-9));
}
/* Info note box - light theme friendly */
.info-note-box {
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
}

.toggle-switch {
  position: relative;
  width: 44px;
  height: 24px;
  background: rgb(var(--slate-6));
  border-radius: 12px;
  border: none;
  cursor: pointer;
  transition: background 0.2s;
  flex-shrink: 0;
  padding: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on {
  background: rgb(var(--blue-9));
}
.toggle-thumb {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 18px;
  height: 18px;
  background: #fff;
  border-radius: 50%;
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  padding: 0 !important;
  margin: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on .toggle-thumb {
  transform: translateX(20px);
}

/* Campos do formulário */
.fields-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.field-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  background: rgb(var(--slate-2));
  border-radius: 8px;
  border: 1px solid rgb(var(--slate-4));
}
.field-drag {
  color: rgb(var(--slate-9));
  cursor: grab;
}
.field-main {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
}
.field-label-text {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}
.field-type-tag {
  @apply text-sm;
  padding: 2px 6px;
  border-radius: 4px;
  background: rgb(var(--slate-5));
  color: rgb(var(--slate-10));
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.field-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}
.field-req-badge {
  @apply text-sm;
  padding: 2px 6px;
  border-radius: 4px;
  background: rgb(var(--ruby-3));
  color: rgb(var(--ruby-11));
}
/* Seletor de agente (admin) */
.agent-selector-wrap {
  margin-bottom: 14px;
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.agent-selector-label {
  display: flex;
  align-items: center;
  gap: 5px;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.agent-selector-select {
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1.5px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 8px 10px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-family: inherit;
  cursor: pointer;
  transition: border-color 0.15s;
  outline: none;
}
.agent-selector-select:focus {
  border-color: rgb(var(--blue-8));
}
</style>
