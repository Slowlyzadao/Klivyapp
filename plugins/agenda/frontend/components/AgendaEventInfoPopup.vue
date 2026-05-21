<script>
import {
  STATUS_OPTIONS,
  STATUS_CONFIGS,
  getEventTypeMeta,
} from '../utils/agenda-constants.js';
import { formatEventTime } from '../utils/agenda-date.js';
import TelemedicineJoinButton from '@plugins/telemed/frontend/dashboard/components/TelemedicineJoinButton.vue';

export default {
  name: 'AgendaEventInfoPopup',
  components: { TelemedicineJoinButton },
  props: {
    event: { type: Object, default: null },
    position: { type: Object, default: () => ({ x: 0, y: 0 }) },
    agents: { type: Array, default: () => [] },
    treatmentOptions: { type: Array, default: () => [] },
    customAttributesConfig: { type: Array, default: () => [] },
    statusUpdatingId: { type: [Number, String], default: null },
  },
  emits: ['close', 'edit', 'status-change', 'open-patient'],
  data() {
    return {
      statusOptions: STATUS_OPTIONS,
    };
  },
  computed: {
    agentName() {
      if (!this.event) return '';
      const agent = this.agents.find(a => a.id === this.event.user_id);
      return agent ? agent.name : '';
    },
    agentColor() {
      if (!this.event) return null;
      const agent = this.agents.find(a => a.id === this.event.user_id);
      return agent ? agent.color : null;
    },
    agentAvatar() {
      if (!this.event) return null;
      const agent = this.agents.find(a => a.id === this.event.user_id);
      return agent?.thumbnail || null;
    },
    // PR #6 (follow-up): prefere snapshot inline → lookup por ID em options →
    // fallback NAME (legado). Mesmo padrão de 3 níveis de `getTreatmentColor`.
    treatmentColor() {
      if (this.event?.agenda_service?.color)
        return this.event.agenda_service.color;

      const sid = this.event?.agenda_service_id;
      if (sid != null) {
        const byId = this.treatmentOptions.find(t => t?.id === sid);
        if (byId?.color) return byId.color;
      }

      const name = this.event?.custom_attributes?.treatment;
      if (!name) return null;
      const byName = this.treatmentOptions.find(
        t => (typeof t === 'string' ? t : t.name) === name
      );
      return byName && typeof byName === 'object' ? byName.color : null;
    },
    // PR #6 (follow-up²): live lookup primeiro (`treatmentOptions` vem do
    // store reativo de serviços) → snapshot inline → JSONB legado. Sem o live
    // lookup, rename só refletia após refetch dos eventos.
    treatmentName() {
      const sid = this.event?.agenda_service_id;
      if (sid != null && this.treatmentOptions?.length) {
        const byId = this.treatmentOptions.find(t => t?.id === sid);
        if (byId?.name) return byId.name;
      }
      return (
        this.event?.agenda_service?.name ||
        this.event?.custom_attributes?.treatment ||
        ''
      );
    },
    initials() {
      const source = this.event?.title || '';
      const parts = source.trim().split(/\s+/).filter(Boolean);
      if (!parts.length) return '?';
      if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    },
    formattedTime() {
      if (!this.event) return '';
      const start = formatEventTime(this.event.starts_at);
      const end = formatEventTime(this.event.ends_at);
      return `${start} – ${end}`;
    },
    popupStyle() {
      if (!this.position) return {};
      const isMobile = window.innerWidth < 768;
      if (isMobile) {
        return {
          position: 'fixed',
          bottom: '0',
          left: '0',
          right: '0',
          width: '100%',
          borderRadius: '20px 20px 0 0',
          zIndex: 10001,
        };
      }

      const popupWidth = 350;
      const margin = 12;

      // Fallbacks caso position venha incompleto (ex: trigger via texto interno do evento)
      const evLeft = this.position.x || 0;
      const evWidth = this.position.width || 0;
      const evRight = this.position.right || evLeft + evWidth;

      let targetX = evRight + margin;

      // Se não couber na direita, tenta abrir na esquerda
      if (targetX + popupWidth > window.innerWidth) {
        targetX = evLeft - popupWidth - margin;
      }

      // Se ainda não couber (janela estreita e evento largo), prende às bordas minimizando overlap
      if (targetX < 10) {
        if (evLeft > popupWidth) {
          targetX = 10;
        } else {
          targetX = window.innerWidth - popupWidth - 10;
        }
        if (targetX < 10) targetX = 10;
      }

      // Calcula Y garantindo que não corte no rodapé do monitor
      let targetY = this.position.y || 0;
      const approxHeight = 520; // Margem de segurança maior devido aos atributos customizados

      if (targetY + approxHeight > window.innerHeight) {
        // Se ultrapassar, alinha pelo fundo da tela ao invés de calcular um Top preciso
        return {
          position: 'fixed',
          bottom: `${margin}px`,
          left: `${targetX}px`,
          width: `${popupWidth}px`,
          maxHeight: `calc(100vh - ${margin * 2}px)`,
          overflowY: 'auto',
          zIndex: 10001,
        };
      }

      return {
        position: 'fixed',
        top: `${Math.max(10, targetY)}px`,
        left: `${targetX}px`,
        width: `${popupWidth}px`,
        zIndex: 10001,
      };
    },
    displayCustomAttributes() {
      if (!this.event || !this.event.custom_values) return [];
      const vals = this.event.custom_values;
      return this.customAttributesConfig
        .filter(attr => vals[attr.attribute_key])
        .map(attr => ({
          label: attr.attribute_display_name,
          value: vals[attr.attribute_key],
        }));
    },
    eventTypeMeta() {
      return getEventTypeMeta(this.event?.event_type || 'consultation');
    },
    // Sprint K — uma consulta com o flag ativo é teleconsulta. Não usamos
    // event_type separado (uma teleconsulta É uma consulta).
    isTelemedicine() {
      return this.event?.custom_attributes?.telemedicine_enabled === true;
    },
    contextLabel() {
      // Quando é teleconsulta, sobrescreve o "DETALHES DO AGENDAMENTO"
      // pra deixar claro que esse card oferece a sala de vídeo.
      if (this.isTelemedicine) return 'Detalhes da Teleconsulta';
      return this.eventTypeMeta.contextLabel;
    },
    showStatusSection() {
      // Status (Agendado/Confirmado/Chegou/...) só faz sentido pra Consulta.
      // Compromisso e Bloqueio não têm fluxo de atendimento.
      return this.eventTypeMeta.value === 'consultation';
    },
    observationText() {
      if (!this.event) return '';
      // Modal salva em `description` (textarea principal). Pra compat com
      // eventos legados que guardavam em custom_attributes.observation,
      // usamos `description` primeiro e caímos pro custom_attribute.
      return (
        this.event.description ||
        this.event.custom_attributes?.observation ||
        ''
      );
    },
  },
  methods: {
    statusColor(key) {
      return (STATUS_CONFIGS[key] && STATUS_CONFIGS[key].color) || '#9ca3af';
    },
  },
};
</script>

<template>
  <Teleport to="body">
    <transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
      enter-to-class="opacity-100 translate-y-0 sm:scale-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 translate-y-0 sm:scale-100"
      leave-to-class="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
    >
      <div v-if="event" class="evt-info-overlay" @click="$emit('close')">
        <div
          class="evt-info-popup bg-white dark:bg-slate-800 rounded-xl shadow-[0_20px_50px_-12px_rgba(0,0,0,0.5)] relative overflow-hidden ring-1 ring-black/5 dark:ring-white/10"
          :style="popupStyle"
          @click.stop
        >
          <!-- Header (Patient Info) -->
          <div
            class="p-4 pb-3 border-b border-slate-100 dark:border-slate-700/60 sticky top-0 bg-white dark:bg-slate-800 z-10 w-full"
          >
            <div class="flex items-center gap-3">
              <!-- Avatar pra Consulta (foto/iniciais do paciente),
                   ícone do tipo pra Compromisso/Bloqueio -->
              <div
                v-if="
                  eventTypeMeta.value === 'consultation' &&
                  event.contact?.avatar_url
                "
                class="size-8 rounded-full overflow-hidden flex-shrink-0 ring-2 ring-white dark:ring-slate-700/40 shadow-sm"
              >
                <img
                  :src="event.contact.avatar_url"
                  class="size-full object-cover"
                />
              </div>
              <div
                v-else-if="eventTypeMeta.value === 'consultation'"
                class="size-8 rounded-full flex items-center justify-center text-xs font-semibold flex-shrink-0 ring-2 ring-white dark:ring-slate-700/40 shadow-sm"
                :style="
                  agentColor
                    ? {
                        background: `color-mix(in srgb, ${agentColor} 18%, transparent)`,
                        color: agentColor,
                        borderColor: `color-mix(in srgb, ${agentColor} 35%, transparent)`,
                        borderWidth: '1px',
                        borderStyle: 'solid',
                      }
                    : null
                "
                :class="
                  agentColor
                    ? ''
                    : 'bg-blue-500/10 text-blue-600 dark:text-blue-400'
                "
              >
                {{ initials }}
              </div>
              <div
                v-else
                class="size-8 rounded-xl flex items-center justify-center flex-shrink-0 shadow-sm"
                :style="{
                  background: `color-mix(in srgb, ${eventTypeMeta.color} 18%, transparent)`,
                  color: eventTypeMeta.color,
                  borderColor: `color-mix(in srgb, ${eventTypeMeta.color} 35%, transparent)`,
                  borderWidth: '1px',
                  borderStyle: 'solid',
                }"
              >
                <i class="size-4" :class="[eventTypeMeta.icon]" />
              </div>
              <div class="min-w-0 flex-1">
                <h3
                  class="text-base font-bold text-slate-900 dark:text-white truncate leading-tight"
                >
                  {{ event.title }}
                </h3>
                <p
                  class="text-[10px] font-bold uppercase tracking-widest mt-0.5"
                  :class="
                    isTelemedicine
                      ? 'text-blue-600 dark:text-blue-400'
                      : 'text-slate-400 dark:text-slate-500'
                  "
                >
                  <i
                    v-if="isTelemedicine"
                    class="i-lucide-video size-3 inline-block align-middle mr-1"
                  />
                  {{ contextLabel }}
                </p>
              </div>
              <button
                class="size-8 flex items-center justify-center rounded-lg hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 transition-colors"
                @click="$emit('close')"
              >
                <i class="i-lucide-x size-4" />
              </button>
            </div>
          </div>

          <!-- Body (Info Rows) -->
          <div class="p-4 space-y-3.5">
            <div class="flex gap-3 items-center">
              <div
                class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400"
              >
                <i class="i-lucide-clock size-4" />
              </div>
              <div class="leading-tight">
                <p
                  class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5"
                >
                  Horário
                </p>
                <p
                  class="text-sm font-semibold text-slate-700 dark:text-slate-200 leading-none"
                >
                  {{ formattedTime }}
                </p>
              </div>
            </div>

            <div v-if="agentName" class="flex gap-3 items-center">
              <div
                v-if="agentAvatar"
                class="size-8 rounded-full overflow-hidden flex-shrink-0 ring-1 ring-slate-200 dark:ring-slate-700"
              >
                <img
                  :src="agentAvatar"
                  :alt="agentName"
                  class="size-full object-cover"
                />
              </div>
              <div
                v-else
                class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400"
              >
                <i class="i-lucide-user size-4" />
              </div>
              <div class="min-w-0 leading-tight">
                <p
                  class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5"
                >
                  Profissional
                </p>
                <div class="flex items-center gap-1.5">
                  <span
                    v-if="agentColor"
                    class="info-dot"
                    :style="{ background: agentColor }"
                  />
                  <p
                    class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate leading-none"
                  >
                    {{ agentName }}
                  </p>
                </div>
              </div>
            </div>

            <div v-if="treatmentName" class="flex gap-3 items-center">
              <div
                class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400"
              >
                <i class="i-lucide-stethoscope size-4" />
              </div>
              <div class="min-w-0 leading-tight">
                <p
                  class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5"
                >
                  Serviço
                </p>
                <div class="flex items-center gap-1.5">
                  <span
                    v-if="treatmentColor"
                    class="info-dot"
                    :style="{ background: treatmentColor }"
                  />
                  <p
                    class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate leading-none"
                  >
                    {{ treatmentName }}
                  </p>
                </div>
              </div>
            </div>

            <div v-if="event.category" class="flex gap-3 items-center">
              <div
                class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400"
              >
                <i class="i-lucide-tag size-4" />
              </div>
              <div class="min-w-0 leading-tight">
                <p
                  class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5"
                >
                  Categoria
                </p>
                <div class="flex items-center gap-1.5">
                  <span
                    v-if="event.category.color"
                    class="info-dot"
                    :style="{ background: event.category.color }"
                  />
                  <p
                    class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate leading-none"
                  >
                    {{ event.category.name }}
                  </p>
                </div>
              </div>
            </div>

            <div
              v-if="observationText"
              class="bg-yellow-50 dark:bg-yellow-500/10 rounded-lg p-3 border border-yellow-200 dark:border-yellow-500/20"
            >
              <div class="flex items-center gap-2 mb-1">
                <i
                  class="i-lucide-message-square text-yellow-600 dark:text-yellow-400 size-3.5"
                />
                <span
                  class="text-[10px] font-bold text-yellow-700 dark:text-yellow-500 uppercase tracking-widest"
                  >Observações</span>
              </div>
              <p
                class="text-sm text-slate-700 dark:text-slate-300 leading-relaxed italic whitespace-pre-line"
                v-text="observationText"
              />
            </div>
          </div>

          <!-- Status Section — apenas Consulta tem fluxo de atendimento -->
          <div
            v-if="showStatusSection"
            class="px-4 py-3 bg-slate-50/80 dark:bg-slate-900/40 border-y border-slate-100 dark:border-slate-700/60 sticky bottom-[64.5px] z-10 w-full backdrop-blur-md"
          >
            <p
              class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest mb-2.5"
            >
              Atualizar Status
            </p>
            <div class="grid grid-cols-2 gap-2">
              <button
                v-for="opt in statusOptions"
                :key="opt.key"
                class="flex items-center gap-2 px-2.5 py-1.5 rounded-lg transition-all text-[13px] font-semibold"
                :class="
                  event.status === opt.key
                    ? 'bg-white dark:bg-slate-800/80 text-blue-700 dark:text-blue-400 shadow-[0_1px_3px_rgba(0,0,0,0.08)] dark:shadow-black/20 ring-1 ring-blue-200 dark:ring-blue-500/30'
                    : 'bg-transparent dark:bg-slate-800/30 text-slate-600 dark:text-slate-300 hover:bg-white dark:hover:bg-slate-700/80 hover:text-slate-800 dark:hover:text-slate-100 border border-transparent hover:border-slate-200 dark:border-slate-700/50 dark:hover:border-slate-600'
                "
                @click="$emit('status-change', { event, status: opt.key })"
              >
                <span
                  class="size-2 rounded-full flex-shrink-0"
                  :style="{ background: statusColor(opt.key) }"
                />
                <span class="truncate">{{ opt.label }}</span>
              </button>
            </div>
          </div>

          <!-- Footer Actions -->
          <div class="p-3 bg-white dark:bg-slate-800 flex gap-2">
            <button
              class="flex-1 h-10 flex items-center justify-center gap-2 bg-white dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 font-bold text-sm rounded-lg border border-slate-200 dark:border-slate-700 shadow-sm transition-all active:scale-95"
              @click="$emit('edit', event)"
            >
              <i class="i-lucide-pencil size-4" />
              Editar
            </button>
            <!-- Sprint K — Botão "Entrar na sala". Renderiza-se sozinho
                 condicionalmente (telemedicine_enabled + user é o profissional
                 responsável + janela aberta). Quando não aplica, o componente
                 retorna nada e o layout do footer continua certinho. -->
            <TelemedicineJoinButton
              v-if="isTelemedicine"
              :event="event"
              class="flex-1"
            />
            <button
              v-if="event.contact_id"
              class="flex-1 h-10 flex items-center justify-center gap-2 bg-blue-600 dark:bg-blue-600 hover:bg-blue-700 dark:hover:bg-blue-500 text-white font-bold text-sm rounded-lg shadow-sm shadow-blue-200 dark:shadow-none transition-all active:scale-95"
              @click="$emit('open-patient', event)"
            >
              <i class="i-lucide-external-link size-4" />
              Prontuário
            </button>
          </div>
        </div>
      </div>
    </transition>
  </Teleport>
</template>

<style scoped>
.evt-info-overlay {
  position: fixed;
  inset: 0;
  background: transparent;
  z-index: 10000;
}

.info-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
  box-shadow:
    0 0 0 1.5px #fff,
    0 0 0 2px rgba(0, 0, 0, 0.08);
}

@media (max-width: 767px) {
  .evt-info-overlay {
    background: rgba(15, 23, 42, 0.4);
    backdrop-filter: blur(4px);
  }
}
</style>
