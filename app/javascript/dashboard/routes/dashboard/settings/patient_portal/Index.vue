<script>
// Página admin de configuração do Portal do Paciente (Sprint G).
//
// Permite ao admin (1) ver setting vigente, (2) trocar preset, (3) inspecionar
// chaves jsonb relevantes (scheduling/financial/messaging/etc).
//
// Edição granular fica como próximo passo — MVP foca em transparência + troca
// de preset, que cobre 90% dos casos de uso.
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PresetCard from './PresetCard.vue';
import SettingSection from './SettingSection.vue';
import KeyValueRow from './KeyValueRow.vue';
import PatientPortalSettingsAPI from 'dashboard/api/patientPortal/settings.js';

const PRESETS = [
  {
    key: 'autonomy_guided',
    title: 'Autonomia guiada',
    summary:
      'Padrão MVP. Paciente pode solicitar agendamento, baixar documentos, pagar online. Recepção aprova quando necessário.',
  },
  {
    key: 'reception_digital',
    title: 'Recepção digital',
    summary:
      'Tudo passa por aprovação humana. Bom pra clínicas que querem controle total enquanto adaptam fluxo.',
  },
  {
    key: 'self_service',
    title: 'Autoatendimento',
    summary:
      'Paciente confirma sem intervenção em ações de baixo risco. Indicado pra alto volume e baixa complexidade.',
  },
  {
    key: 'concierge',
    title: 'Concierge',
    summary:
      'Atendimento premium. Mensageria liberada com profissional, recibos automáticos, agendamento amplo.',
  },
];

export default {
  components: {
    SettingsLayout,
    BaseSettingsHeader,
    NextButton,
    PresetCard,
    SettingSection,
    KeyValueRow,
  },
  data() {
    return {
      setting: null,
      loading: true,
      applying: null, // preset_key sendo aplicado
    };
  },
  computed: {
    ...mapGetters({ accountId: 'getCurrentAccountId' }),
    activePreset() { return this.setting?.active_preset ?? 'autonomy_guided'; },
    presets()      { return PRESETS; },
    scheduling()   { return this.setting?.scheduling ?? {}; },
    financial()    { return this.setting?.financial ?? {}; },
    messaging()    { return this.setting?.messaging ?? {}; },
    documents()    { return this.setting?.documents ?? {}; },
  },
  mounted() { this.load(); },
  methods: {
    async load() {
      this.loading = true;
      try {
        const { data } = await PatientPortalSettingsAPI.show();
        this.setting = data.data;
      } catch (e) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR') || 'Não foi possível carregar.');
      } finally {
        this.loading = false;
      }
    },
    async applyPreset(presetKey) {
      if (this.applying || presetKey === this.activePreset) return;
      this.applying = presetKey;
      try {
        const { data } = await PatientPortalSettingsAPI.applyPreset(presetKey);
        this.setting = data.data;
        useAlert('Preset aplicado com sucesso.');
      } catch (e) {
        useAlert(e?.response?.data?.errors?.[0]?.message || 'Falha ao aplicar preset.');
      } finally {
        this.applying = null;
      }
    },
  },
};
</script>

<template>
  <SettingsLayout
    :is-loading="loading"
    :loading-message="'Carregando configurações...'"
  >
    <template #header>
      <BaseSettingsHeader
        title="Portal do Paciente"
        description="Defina como os pacientes interagem com sua clínica via portal — preset, agendamento, mensageria e pagamento."
        :link-text="''"
        feature-name="patient_portal"
      />
    </template>
    <template #body>
      <div class="grid gap-6 px-1 pb-8 max-w-4xl">
        <!-- Preset selector -->
        <SettingSection
          title="Preset"
          subtitle="Combo pré-definido de regras. Escolha o que melhor representa o fluxo da clínica — você pode customizar no jsonb depois."
        >
          <div class="grid gap-3 sm:grid-cols-2">
            <PresetCard
              v-for="p in presets"
              :key="p.key"
              :preset-key="p.key"
              :title="p.title"
              :summary="p.summary"
              :active="activePreset === p.key"
              :disabled="!!applying"
              @select="applyPreset"
            />
          </div>
          <p class="text-xs text-n-slate-11 mt-2">
            Preset ativo:
            <strong class="text-n-slate-12">{{ activePreset }}</strong>
          </p>
        </SettingSection>

        <!-- Scheduling read-only -->
        <SettingSection
          title="Agendamento"
          subtitle="Regras vigentes que o portal aplica ao paciente."
        >
          <KeyValueRow label="Modo" :value="scheduling.scheduling_mode" />
          <KeyValueRow label="Primeira consulta" :value="scheduling.first_visit_mode" />
          <KeyValueRow label="Antecedência mínima (h)" :value="scheduling.min_lead_time_hours" />
          <KeyValueRow label="Janela futura (dias)" :value="scheduling.max_future_days" />
          <KeyValueRow label="Permite no mesmo dia" :value="!!scheduling.allow_same_day" />
          <KeyValueRow label="Bloqueia se inadimplente" :value="!!scheduling.block_if_overdue" />
        </SettingSection>

        <!-- Financial read-only -->
        <SettingSection
          title="Financeiro"
          subtitle="Quais ações de pagamento ficam liberadas no portal."
        >
          <KeyValueRow label="Métodos de pagamento" :value="financial.payment_methods || []" />
          <KeyValueRow label="Mostra histórico" :value="!!financial.show_paid_history" />
          <KeyValueRow label="Bloqueia portal por dias em atraso" :value="financial.block_portal_if_overdue_days" />
        </SettingSection>

        <!-- Messaging read-only -->
        <SettingSection
          title="Mensageria"
          subtitle="Conversa no portal. As keywords de urgência disparam o modal de triagem."
        >
          <KeyValueRow label="Habilitada" :value="!!messaging.messaging_enabled" />
          <KeyValueRow label="Direta com profissional" :value="!!messaging.allow_direct_professional" />
          <KeyValueRow label="Keywords de urgência" :value="messaging.urgent_keyword_list || []" />
          <KeyValueRow label="Ação ao detectar urgência" :value="messaging.urgent_action" />
        </SettingSection>

        <!-- Documents read-only -->
        <SettingSection
          title="Documentos"
          subtitle="Quais tipos ficam expostos no portal e quais podem ser pedidos."
        >
          <KeyValueRow label="Tipos visíveis" :value="documents.document_types_exposed || []" />
          <KeyValueRow label="Solicitação habilitada" :value="!!documents.allow_document_request" />
          <KeyValueRow label="Aprovação automática (simples)" :value="!!documents.auto_approve_simple_requests" />
          <KeyValueRow label="TTL link compartilhado (min)" :value="documents.document_link_ttl_minutes" />
        </SettingSection>

        <p class="text-xs text-n-slate-11 mt-2">
          Edição granular dos jsonbs entra em fase futura. Hoje, alterar via preset ou via API
          <code class="px-1 py-0.5 bg-n-solid-2 rounded">PATCH /api/v1/accounts/:id/patient_portal/setting</code>.
        </p>
      </div>
    </template>
  </SettingsLayout>
</template>
