<script>
import { STATUS_OPTIONS, STATUS_CONFIGS } from '../utils/agenda-constants.js';
import { formatEventTime } from '../utils/agenda-date.js';

export default {
  name: 'AgendaEventInfoPopup',
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
    treatmentColor() {
      const name = this.event?.custom_attributes?.treatment;
      if (!name) return null;
      const found = this.treatmentOptions.find(
        t => (typeof t === 'string' ? t : t.name) === name
      );
      return found && typeof found === 'object' ? found.color : null;
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
          zIndex: 10001
        };
      }
      
      const popupWidth = 350;
      const margin = 12;
      
      // Fallbacks caso position venha incompleto (ex: trigger via texto interno do evento)
      const evLeft = this.position.x || 0;
      const evWidth = this.position.width || 0;
      const evRight = this.position.right || (evLeft + evWidth);
      
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
          zIndex: 10001
        };
      }

      return {
        position: 'fixed',
        top: `${Math.max(10, targetY)}px`,
        left: `${targetX}px`,
        width: `${popupWidth}px`,
        zIndex: 10001
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
          <div class="p-4 pb-3 border-b border-slate-100 dark:border-slate-700/60 sticky top-0 bg-white dark:bg-slate-800 z-10 w-full">
            <div class="flex items-center gap-3">
              <div v-if="event.contact?.avatar_url" class="size-10 rounded-full overflow-hidden flex-shrink-0 ring-2 ring-white dark:ring-slate-700/40 shadow-sm">
                <img :src="event.contact.avatar_url" class="size-full object-cover" />
              </div>
              <div
                v-else
                class="size-10 rounded-full flex items-center justify-center text-xs font-semibold flex-shrink-0 ring-2 ring-white dark:ring-slate-700/40 shadow-sm"
                :style="agentColor ? { background: `color-mix(in srgb, ${agentColor} 18%, transparent)`, color: agentColor, borderColor: `color-mix(in srgb, ${agentColor} 35%, transparent)`, borderWidth: '1px', borderStyle: 'solid' } : null"
                :class="agentColor ? '' : 'bg-blue-500/10 text-blue-600 dark:text-blue-400'"
              >
                {{ initials }}
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="text-base font-bold text-slate-900 dark:text-white truncate leading-tight">{{ event.title }}</h3>
                <p class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest mt-0.5">Detalhes do Agendamento</p>
              </div>
              <button @click="$emit('close')" class="size-8 flex items-center justify-center rounded-lg hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 transition-colors">
                <i class="i-lucide-x size-4" />
              </button>
            </div>
          </div>

          <!-- Body (Info Rows) -->
          <div class="p-4 space-y-3.5">
            <div class="flex gap-3 items-center">
              <div class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400">
                <i class="i-lucide-clock size-4" />
              </div>
              <div class="leading-tight">
                <p class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5">Horário</p>
                <p class="text-sm font-semibold text-slate-700 dark:text-slate-200 leading-none">{{ formattedTime }}</p>
              </div>
            </div>

            <div v-if="agentName" class="flex gap-3 items-center">
              <div class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400">
                <i class="i-lucide-user size-4" />
              </div>
              <div class="min-w-0 leading-tight">
                <p class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5">Profissional</p>
                <div class="flex items-center gap-1.5">
                  <span
                    v-if="agentColor"
                    class="info-dot"
                    :style="{ background: agentColor }"
                  />
                  <p class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate leading-none">{{ agentName }}</p>
                </div>
              </div>
            </div>

            <div v-if="event.custom_attributes?.treatment" class="flex gap-3 items-center">
              <div class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400">
                <i class="i-lucide-stethoscope size-4" />
              </div>
              <div class="min-w-0 leading-tight">
                <p class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5">Serviço</p>
                <div class="flex items-center gap-1.5">
                  <span
                    v-if="treatmentColor"
                    class="info-dot"
                    :style="{ background: treatmentColor }"
                  />
                  <p class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate leading-none">{{ event.custom_attributes.treatment }}</p>
                </div>
              </div>
            </div>

            <div v-if="event.category" class="flex gap-3 items-center">
              <div class="size-8 rounded-lg bg-slate-50 dark:bg-slate-700/50 flex items-center justify-center flex-shrink-0 text-slate-400 dark:text-slate-400">
                <i class="i-lucide-tag size-4" />
              </div>
              <div class="min-w-0 leading-tight">
                <p class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest leading-none mb-0.5">Categoria</p>
                <div class="flex items-center gap-1.5">
                  <span
                    v-if="event.category.color"
                    class="info-dot"
                    :style="{ background: event.category.color }"
                  />
                  <p class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate leading-none">{{ event.category.name }}</p>
                </div>
              </div>
            </div>

            <div v-if="event.custom_attributes?.observation" class="bg-amber-50/50 dark:bg-amber-500/10 rounded-lg p-3 border border-amber-100/50 dark:border-amber-500/20">
               <div class="flex items-center gap-2 mb-1">
                 <i class="i-lucide-message-square text-amber-500 dark:text-amber-400 size-3.5" />
                 <span class="text-[10px] font-bold text-amber-600 dark:text-amber-500 uppercase tracking-widest">Observação</span>
               </div>
               <p class="text-sm text-slate-600 dark:text-slate-300 leading-relaxed italic" v-text="event.custom_attributes.observation" />
            </div>
          </div>

          <!-- Status Section -->
          <div class="px-4 py-3 bg-slate-50/80 dark:bg-slate-900/40 border-y border-slate-100 dark:border-slate-700/60 sticky bottom-[64.5px] z-10 w-full backdrop-blur-md">
            <p class="text-[10px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest mb-2.5">Atualizar Status</p>
            <div class="grid grid-cols-2 gap-2">
              <button
                v-for="opt in statusOptions"
                :key="opt.key"
                @click="$emit('status-change', { event, status: opt.key })"
                class="flex items-center gap-2 px-2.5 py-1.5 rounded-lg transition-all text-[13px] font-semibold"
                :class="event.status === opt.key 
                  ? 'bg-white dark:bg-slate-800/80 text-blue-700 dark:text-blue-400 shadow-[0_1px_3px_rgba(0,0,0,0.08)] dark:shadow-black/20 ring-1 ring-blue-200 dark:ring-blue-500/30' 
                  : 'bg-transparent dark:bg-slate-800/30 text-slate-600 dark:text-slate-300 hover:bg-white dark:hover:bg-slate-700/80 hover:text-slate-800 dark:hover:text-slate-100 border border-transparent hover:border-slate-200 dark:border-slate-700/50 dark:hover:border-slate-600'"
              >
                <span class="size-2 rounded-full flex-shrink-0" :style="{ background: statusColor(opt.key) }" />
                <span class="truncate">{{ opt.label }}</span>
              </button>
            </div>
          </div>

          <!-- Footer Actions -->
          <div class="p-3 bg-white dark:bg-slate-800 flex gap-2">
            <button @click="$emit('edit', event)" class="flex-1 h-10 flex items-center justify-center gap-2 bg-white dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 font-bold text-sm rounded-lg border border-slate-200 dark:border-slate-700 shadow-sm transition-all active:scale-95">
              <i class="i-lucide-pencil size-4" />
              Editar
            </button>
            <button v-if="event.contact_id" @click="$emit('open-patient', event)" class="flex-1 h-10 flex items-center justify-center gap-2 bg-blue-600 dark:bg-blue-600 hover:bg-blue-700 dark:hover:bg-blue-500 text-white font-bold text-sm rounded-lg shadow-sm shadow-blue-200 dark:shadow-none transition-all active:scale-95">
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
  box-shadow: 0 0 0 1.5px #fff, 0 0 0 2px rgba(0, 0, 0, 0.08);
}

@media (max-width: 767px) {
  .evt-info-overlay {
    background: rgba(15, 23, 42, 0.4);
    backdrop-filter: blur(4px);
  }
}
</style>

