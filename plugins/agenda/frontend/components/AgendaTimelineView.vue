<script>
import AgendaEventCard from './AgendaEventCard.vue';
import AgendaDragGhost from './AgendaDragGhost.vue';
import { parseEventDate, formatEventTime, getEventSizeTier } from '../utils/agenda-date.js';
import { pastelBgFromColor, opaquePastelFromColor, darkenedTextColor, translucentBgFromColor } from '../utils/agenda-colors.js';

const MIN_EVENT_HEIGHT_PX = 28;

export default {
  name: 'AgendaTimelineView',
  components: { AgendaEventCard, AgendaDragGhost },
  props: {
    viewMode: { type: String, required: true },
    layoutMode: { type: String, default: 'side-by-side' },
    activeAgents: { type: Array, default: () => [] },
    currentWeekDays: { type: Array, default: () => [] },
    currentDayObj: { type: Object, default: () => ({}) },
    dayHours: { type: Array, required: true },
    rowHeight: { type: Number, default: 80 },
    pixelsPerHour: { type: Number, default: 80 },
    slotIntervalMinutes: { type: Number, default: 60 },
    visibleStartHour: { type: Number, default: 0 },
    agendaEvents: { type: Array, default: () => [] },
    agentList: { type: Array, default: () => [] },
    currentUserID: { type: [Number, String], default: null },
    isAdmin: { type: Boolean, default: false },
    currentTimeLineStyle: { type: Object, default: () => ({}) },
    // Drag state
    isDragging: { type: Boolean, default: false },
    draggingEvent: { type: Object, default: null },
    draggingEventId: { type: [Number, String], default: null },
    dragCurrentDayObj: { type: Object, default: null },
    dragCurrentStartsAt: { type: String, default: null },
    dragCurrentEndsAt: { type: String, default: null },
    dragGhostStyle: { type: Object, default: () => ({}) },
    dragIsBlocked: { type: Boolean, default: false },
    dragBlockReason: { type: String, default: null },
    // Resize state
    isResizing: { type: Boolean, default: false },
    resizingEventId: { type: [Number, String], default: null },
    resizingEventEndAt: { type: String, default: null },
    // Methods passed as props
    isHourBlocked: { type: Function, required: true },
    getWaitingListMatchForCell: { type: Function, required: true },
    getEventsForDay: { type: Function, required: true },
    calculateOverlaps: { type: Function, required: true },
    getEventBackground: { type: Function, required: true },
    getAgentColor: { type: Function, required: true },
    getTreatmentColor: { type: Function, default: () => null },
    getCategoryColor: { type: Function, default: () => null },
    getStatusConfig: { type: Function, required: true },
    isEventLate: { type: Function, required: true },
    getDayBlockInfo: { type: Function, default: () => [] },
    isDarkTheme: { type: Boolean, default: true },
  },
  emits: [
    'click-cell',
    'click-event',
    'init-drag',
    'init-resize',
    'wl-cell-click',
    'quick-delete',
  ],
  computed: {
    columns() {
      if (this.viewMode === 'week') return this.currentWeekDays;
      return this.activeAgents;
    },
    dynamicColWidth() {
      if (this.viewMode === 'day' && this.activeAgents.length > 7) {
        return 'calc((100cqi - 64px) / 7)';
      }
      return '0px';
    },
    showTimeLine() {
      if (this.viewMode === 'week') return true;
      return this.isToday(this.currentDayObj);
    },
  },
  methods: {
    formatEventTime,
    getEventSizeTier,
    isToday(dayObj) {
      const n = new Date();
      return (
        dayObj.day === n.getDate() &&
        dayObj.month === n.getMonth() &&
        dayObj.year === n.getFullYear()
      );
    },
    isWeekend(dayObj) {
      const dow = new Date(dayObj.year, dayObj.month, dayObj.day).getDay();
      return dow === 0 || dow === 6;
    },
    getColumnEventsWithPositions(colItem) {
      // Day view: coluna É o agente — filtra eventos pelo agente da coluna,
      // calcula overlaps internos, renderiza ocupando 100% da largura.
      if (this.viewMode === 'day') {
        const dayEvents = this.getEventsForDay(this.currentDayObj);
        const filtered = dayEvents.filter(e => e.user_id === colItem.id);
        const withOverlaps = this.calculateOverlaps(filtered);
        return withOverlaps.map(event => ({
          ...event,
          _style: this.getEventTimelineStyle(event, event.totalCols, event.colIdx),
          _agentColor: this.getAgentColor(event),
          _treatmentColor: this.getTreatmentColor(event),
          _bg: this.getEventBackground(event),
        }));
      }

      // Week view: divide a coluna do dia em sub-colunas (lanes) por agente.
      // Cada agente que tem evento naquele dia ganha uma fatia igual da
      // largura total. Dentro da lane do agente, overlaps internos são
      // resolvidos pelo `calculateOverlaps` clássico — então 2 consultas
      // sobrepostas do mesmo agente continuam dividindo a lane dele em duas.
      const dayObj = colItem;
      const lanes = this.getDayAgentLanes(dayObj);
      const laneByAgent = new Map(lanes.map(l => [l.agentId, l]));

      // Agrupa por agente
      const dayEvents = this.getEventsForDay(dayObj);
      const buckets = new Map();
      const orphans = [];
      for (const e of dayEvents) {
        if (e.user_id && laneByAgent.has(e.user_id)) {
          if (!buckets.has(e.user_id)) buckets.set(e.user_id, []);
          buckets.get(e.user_id).push(e);
        } else {
          orphans.push(e);
        }
      }

      const result = [];
      for (const [agentId, events] of buckets) {
        const lane = laneByAgent.get(agentId);
        const withOverlaps = this.calculateOverlaps(events);
        for (const ev of withOverlaps) {
          result.push({
            ...ev,
            _style: this.getEventTimelineStyle(ev, ev.totalCols, ev.colIdx, lane),
            _agentColor: this.getAgentColor(ev),
            _treatmentColor: this.getTreatmentColor(ev),
            _bg: this.getEventBackground(ev),
          });
        }
      }
      // Eventos sem agente associado: caem em uma "lane fantasma" full-width
      // sob comportamento legado (overlap clássico). Raros — manter simples.
      if (orphans.length) {
        const withOverlaps = this.calculateOverlaps(orphans);
        for (const ev of withOverlaps) {
          result.push({
            ...ev,
            _style: this.getEventTimelineStyle(ev, ev.totalCols, ev.colIdx, null),
            _agentColor: this.getAgentColor(ev),
            _treatmentColor: this.getTreatmentColor(ev),
            _bg: this.getEventBackground(ev),
          });
        }
      }
      return result;
    },
    // Lista as lanes do dia em week view: um slot por agente que tem evento
    // naquele dia. Ordem segue `activeAgents` (estável entre renders) e
    // ignora agentes ocultos pelo filtro. Retorno usado tanto pra calcular
    // a posição dos cards quanto pra renderizar os fundos das lanes.
    getDayAgentLanes(dayObj) {
      if (this.viewMode !== 'week') return [];
      const events = this.getEventsForDay(dayObj);
      const idsInDay = new Set();
      for (const e of events) {
        if (e.user_id) idsInDay.add(e.user_id);
      }
      if (!idsInDay.size) return [];
      const ordered = this.activeAgents.filter(a => idsInDay.has(a.id));
      if (!ordered.length) return [];
      const total = ordered.length;
      const isDark = this.isDarkTheme;
      return ordered.map((agent, idx) => ({
        agentId: agent.id,
        agentColor: agent.color,
        agentName: agent.name,
        agentIdx: idx,
        totalAgents: total,
        leftPct: (idx * 100) / total,
        widthPct: 100 / total,
        // Translúcido (não opaco) para preservar a visibilidade do hatch das
        // células bloqueadas/almoço/feriado que ficam atrás da lane. Em
        // dark mode subimos a alpha — alpha 0.12 sobre fundo escuro fica
        // praticamente invisível.
        bg: translucentBgFromColor(agent.color, isDark ? 0.18 : 0.12),
      }));
    },
    // Agrupa os slots da grade em ranges contínuos de horas NÃO-bloqueadas.
    // Usado para renderizar as lanes do agente apenas dentro das horas de
    // trabalho — bloqueio (almoço, feriado, fora do expediente) interrompe
    // o tint pra que o hatch da célula fique visível e limpo, igual day view.
    getLaneSegments(dayObj) {
      const segments = [];
      let currentStart = null;
      this.dayHours.forEach((hour, idx) => {
        const blocked = this.isHourBlocked(dayObj, hour);
        if (!blocked) {
          if (currentStart === null) currentStart = idx;
        } else if (currentStart !== null) {
          segments.push({ startIdx: currentStart, endIdx: idx - 1 });
          currentStart = null;
        }
      });
      if (currentStart !== null) {
        segments.push({
          startIdx: currentStart,
          endIdx: this.dayHours.length - 1,
        });
      }
      return segments;
    },
    getEventTimelineStyle(event, totalCols, colIdx, agentLane) {
      if (!event.starts_at || !event.ends_at) return {};
      const start = parseEventDate(event.starts_at);

      let endAtForCalc = event.ends_at;
      if (
        this.isResizing &&
        this.resizingEventId === event.id &&
        this.resizingEventEndAt
      ) {
        endAtForCalc = this.resizingEventEndAt;
      }
      const end = parseEventDate(endAtForCalc);

      const interval = this.slotIntervalMinutes || 60;
      const slotHeight = this.rowHeight;
      const visibleStartMin = this.visibleStartHour * 60;
      const startMin = start.getHours() * 60 + start.getMinutes();
      const endMin = end.getHours() * 60 + end.getMinutes();

      // Snap to slot boundaries so the event sits exactly on grid lines.
      // floor() the start so the top aligns with the slot containing
      // start_time; ceil() the end so trailing minutes always fill the
      // last partial slot (per spec: NEVER floor — the bottom must reach
      // the end of the last slot the event touches).
      const snapStartSlot = Math.floor((startMin - visibleStartMin) / interval);
      const snapEndSlot = Math.ceil((endMin - visibleStartMin) / interval);
      const slotsOccupied = Math.max(1, snapEndSlot - snapStartSlot);

      const topOffset = snapStartSlot * slotHeight;
      // Subtract a 2px sliver from the bottom so consecutive events have a
      // visible vertical gap instead of looking glued. Top stays
      // slot-aligned, only the visual height shrinks.
      const heightPx = Math.max(
        MIN_EVENT_HEIGHT_PX,
        slotsOccupied * slotHeight - 2,
      );

      // Posicionamento horizontal:
      //   - Sem agentLane (day view ou orfão em week): o evento ocupa a
      //     coluna toda dividido apenas pelos overlaps internos.
      //   - Com agentLane (week view padrão): o evento vive dentro da lane
      //     do agente. A largura é a fatia da lane dividida pelos overlaps
      //     internos do próprio agente.
      const colCount = totalCols || 1;
      const idx = colIdx || 0;
      let leftPct;
      let widthPct;
      if (agentLane) {
        const innerWidth = agentLane.widthPct / colCount;
        leftPct = agentLane.leftPct + idx * innerWidth;
        widthPct = innerWidth;
      } else {
        widthPct = 100 / colCount;
        leftPct = idx * widthPct;
      }

      // Regra de cor do card (independente de view):
      //   - tem categoria → pastel OPACO da categoria + accent saturado
      //   - não tem        → fundo neutro (branco light / slate-800 dark)
      // Opaco (não rgba) é crucial: o card senta em cima das linhas do grid
      // do calendário; alpha deixa as linhas vazarem e prejudica leitura.
      // A identidade do agente é comunicada pelo wash da lane/coluna, nunca
      // pelo body do card.
      const isDark = this.isDarkTheme;
      const categoryColor = this.getCategoryColor(event);
      const hasCategory = !!categoryColor;
      const bg = hasCategory
        ? opaquePastelFromColor(categoryColor, isDark)
        : (isDark ? 'rgb(30, 41, 59)' : '#ffffff');
      const accent = hasCategory
        ? categoryColor
        : (isDark ? '#475569' : '#cbd5e1');
      const textColor = hasCategory
        ? darkenedTextColor(categoryColor, isDark)
        : (isDark ? '#e2e8f0' : '#1f2937');

      return {
        position: 'absolute',
        top: `${topOffset}px`,
        height: `${heightPx}px`,
        left: `calc(${leftPct}% + 3px)`,
        width: `calc(${widthPct}% - 6px)`,
        background: bg,
        borderLeftColor: accent,
        borderLeftWidth: '4px',
        '--evt-text-color': textColor,
        '--evt-accent-color': accent,
        color: textColor,
        zIndex: this.isDragging && this.draggingEventId === event.id ? 50 : 5,
      };
    },
    // Wash atrás da coluna do agente (apenas day view). Usa exatamente o
    // mesmo cálculo da lane backdrop em week view (`translucentBgFromColor`
    // com mesma alpha) — antes day view usava `pastelBgFromColor` opaco
    // (HSL L=95%) e ficava visualmente diferente do tom translúcido da
    // lane em week. Agora os dois tons batem.
    getAgentColumnTint(agent) {
      if (!agent || !agent.color) return null;
      return translucentBgFromColor(agent.color, this.isDarkTheme ? 0.18 : 0.12);
    },
    isDragInDay(dayObj) {
      if (!this.dragCurrentDayObj) return false;
      return (
        this.dragCurrentDayObj.day === dayObj.day &&
        this.dragCurrentDayObj.month === dayObj.month &&
        this.dragCurrentDayObj.year === dayObj.year
      );
    },
    isDragInAgentCol(agent) {
      if (!this.draggingEvent) return false;
      return this.draggingEvent.user_id === agent.id;
    },
    showDragGhostInCol(colItem) {
      if (!this.isDragging || !this.draggingEvent) return false;
      if (this.viewMode === 'week') {
        return this.isDragInDay(colItem);
      }
      return this.isDragInAgentCol(colItem);
    },
  },
};
</script>

<template>
  <div
    class="timeline-area"
    :class="[viewMode, layoutMode]"
    :style="{ '--dynamic-col-width': dynamicColWidth }"
  >
    <div class="timeline-internal-wrapper">
      <!-- Timeline Header -->
      <div ref="timelineHeaders" class="timeline-headers">
        
        <!-- Day View: Full day events (Holidays, Exceções) -->
        <div v-if="viewMode === 'day' && getDayBlockInfo(currentDayObj).some(b => b.type !== 'closed')" class="timeline-headers-row border-bottom-strong">
           <div class="time-header-spacer" />
           <div class="day-view-blocks-wrapper">
              <template v-for="(block, bIdx) in getDayBlockInfo(currentDayObj)" :key="bIdx">
                 <div v-if="block.type !== 'closed'"
                      class="header-block-banner" 
                      :class="[`block-type-${block.type}`, { 'is-past': block.isPast }]">
                    {{ block.title }}
                 </div>
              </template>
           </div>
        </div>

        <!-- Normal Headers (Week Days or Agents) -->
        <div class="timeline-headers-row">
          <div class="time-header-spacer" />
          <template v-if="viewMode === 'week'">
            <div
              v-for="(dayObj, idx) in currentWeekDays"
              :key="idx"
              class="timeline-day-header"
              :class="{ 'is-today': isToday(dayObj), 'is-weekend': isWeekend(dayObj) }"
            >
              <div style="display: flex; align-items: center; gap: 4px;">
                <span class="day-str">{{ dayObj.label }}</span>
                <i
                  v-if="getDayBlockInfo(dayObj).some(b => b.type === 'closed')"
                  class="i-lucide-lock text-n-slate-8 text-xs"
                  title="Dias fechado"
                />
              </div>
              <div class="day-num-wrap">
                <div class="day-num" :class="{ today: isToday(dayObj) }">
                  {{ dayObj.day }}
                </div>
              </div>
              <div class="header-day-blocks" v-if="getDayBlockInfo(dayObj).some(b => b.type !== 'closed')">
                 <template v-for="(block, bIdx) in getDayBlockInfo(dayObj)" :key="bIdx">
                    <div v-if="block.type !== 'closed'"
                         class="header-block-banner"
                         :class="[`block-type-${block.type}`, { 'is-past': block.isPast }]">
                       {{ block.title }}
                    </div>
                 </template>
              </div>
              <!-- Faixas coloridas dos agentes na borda inferior do header
                   (week view). Mesma proporção das lanes abaixo, então o
                   olho conecta visualmente "topo colorido = começo da lane
                   daquele agente". Substitui o border-top que ficava no
                   primeiro segmento da lane. -->
              <div class="day-header-agent-stripes">
                <div
                  v-for="lane in getDayAgentLanes(dayObj)"
                  :key="`hdr-stripe-${lane.agentId}`"
                  class="day-header-agent-stripe"
                  :title="lane.agentName"
                  :style="{
                    left: `${lane.leftPct}%`,
                    width: `${lane.widthPct}%`,
                    background: lane.agentColor,
                  }"
                />
              </div>
            </div>
          </template>
          <template v-else>
            <div
              v-for="agent in activeAgents"
              :key="agent.id"
              class="timeline-day-header"
              :class="{ 'is-today': isToday(currentDayObj) }"
            >
              <div class="agent-header">
                <div
                  class="agent-color-dot"
                  :style="{ backgroundColor: agent.color }"
                />
                <span class="agent-name-label">{{ agent.name }}</span>
              </div>
            </div>
          </template>
        </div>
      </div>

      <div class="timeline-grid-wrapper">
        <!-- Background Grid Layer -->
        <div class="timeline-grid-background">
          <div
            v-for="hour in dayHours"
            :key="hour"
            class="timeline-row"
            :style="{ height: `${rowHeight}px` }"
          >
            <div class="time-label">{{ hour }}</div>
            <template v-if="viewMode === 'week'">
              <div
                v-for="(dayObj, idx) in currentWeekDays"
                :key="idx"
                :data-col-idx="idx"
                class="timeline-cell"
                :class="{
                  'cell-blocked': isHourBlocked(dayObj, hour),
                  'cell-wl-match':
                    !isHourBlocked(dayObj, hour) &&
                    getWaitingListMatchForCell(dayObj, hour).length > 0,
                }"
                @click="$emit('click-cell', { dayObj, hour })"
              >
                <div
                  v-if="isHourBlocked(dayObj, hour) && !['Passado', 'Fechado'].includes(isHourBlocked(dayObj, hour))"
                  class="blocked-slot-overlay"
                >
                  <i class="i-lucide-lock blocked-slot-icon" />
                  <span class="blocked-slot-tooltip" role="tooltip">
                    {{ isHourBlocked(dayObj, hour) === true ? 'Indisponível' : isHourBlocked(dayObj, hour) }}
                  </span>
                </div>
                <div
                  v-else-if="
                    getWaitingListMatchForCell(dayObj, hour).length > 0
                  "
                  class="wl-cell-actions"
                >
                  <button
                    class="wl-cell-btn"
                    title="Criar novo evento"
                    @click.stop="$emit('click-cell', { dayObj, hour })"
                  >
                    <span class="i-ph-pencil-simple" />
                  </button>
                  <button
                    class="wl-cell-btn wl-cell-btn--wl"
                    title="Agendar paciente da lista de espera"
                    @click.stop="$emit('wl-cell-click', { $event, dayObj, hour })"
                  >
                    <span class="i-ph-clock-countdown" />
                  </button>
                </div>
              </div>
            </template>
            <template v-else>
              <div
                v-for="(agent, aIdx) in activeAgents"
                :key="agent.id"
                :data-col-idx="aIdx"
                class="timeline-cell day-cell"
                :class="{
                  'cell-blocked': isHourBlocked(currentDayObj, hour),
                  'cell-agent-tinted': !isHourBlocked(currentDayObj, hour) && getAgentColumnTint(agent),
                }"
                :style="
                  !isHourBlocked(currentDayObj, hour) && getAgentColumnTint(agent)
                    ? { '--agent-tint': getAgentColumnTint(agent) }
                    : null
                "
                @click="$emit('click-cell', { dayObj: currentDayObj, hour, agent })"
              >
                <div
                  v-if="isHourBlocked(currentDayObj, hour) && isHourBlocked(currentDayObj, hour) !== 'Passado'"
                  class="blocked-slot-overlay"
                >
                  <i class="i-lucide-lock blocked-slot-icon" />
                  <span class="blocked-slot-tooltip" role="tooltip">
                    {{ isHourBlocked(currentDayObj, hour) === true ? 'Indisponível' : isHourBlocked(currentDayObj, hour) }}
                  </span>
                </div>
              </div>
            </template>
          </div>
        </div>

        <!-- Events overlay layer -->
        <div class="timeline-events-layer">
          <div class="time-label-spacer" />
          <!-- Current time line -->
          <div
            v-if="showTimeLine"
            class="current-time-line"
            :style="currentTimeLineStyle"
          >
            <div class="current-time-dot" />
          </div>

          <div
            v-for="(colItem, dIdx) in columns"
            :key="dIdx"
            :data-col-idx="dIdx"
            class="day-events-column"
            :style="{ height: `${dayHours.length * rowHeight}px` }"
          >
            <!-- Lane backdrops (week view): uma faixa pastel por agente
                 quebrada em segmentos contínuos de horas não-bloqueadas.
                 Slots bloqueados (almoço/feriado/fora do expediente) ficam
                 sem tint pra mostrar o hatch limpo, igual day view. A
                 identificação visual do agente vai pra faixa colorida no
                 day header (`.day-header-agent-stripe`) — aqui a lane é só
                 o tint pastel limpo, sem borda. -->
            <template v-if="viewMode === 'week'">
              <template
                v-for="lane in getDayAgentLanes(colItem)"
                :key="`lane-${colItem.year}-${colItem.month}-${colItem.day}-${lane.agentId}`"
              >
                <div
                  v-for="seg in getLaneSegments(colItem)"
                  :key="`lane-${lane.agentId}-${seg.startIdx}`"
                  class="agent-lane-bg"
                  :title="lane.agentName"
                  :style="{
                    top: `${seg.startIdx * rowHeight}px`,
                    height: `${(seg.endIdx - seg.startIdx + 1) * rowHeight}px`,
                    left: `${lane.leftPct}%`,
                    width: `${lane.widthPct}%`,
                    background: lane.bg,
                  }"
                />
              </template>
            </template>

            <AgendaEventCard
              v-for="event in getColumnEventsWithPositions(colItem)"
              :key="event.id"
              :event="event"
              :card-style="event._style"
              :agent-color="event._agentColor"
              :treatment-color="event._treatmentColor"
              :is-resizing-this="isResizing && resizingEventId === event.id"
              :is-dragging-this="isDragging && draggingEventId === event.id"
              :is-late="isEventLate(event)"
              :resizing-end-at="resizingEventEndAt"
              :layout-mode="layoutMode"
              @click="$emit('click-event', { event, $event })"
              @quick-delete="$emit('quick-delete', event)"
              @mousedown-drag="$emit('init-drag', { event, $event })"
              @mousedown-resize="$emit('init-resize', { event, $event })"
            />

            <!-- Drag ghost -->
            <AgendaDragGhost
              v-if="showDragGhostInCol(colItem)"
              :event="draggingEvent"
              :ghost-style="dragGhostStyle"
              :drag-starts-at="dragCurrentStartsAt"
              :drag-ends-at="dragCurrentEndsAt"
              :is-blocked="dragIsBlocked"
              :block-reason="dragBlockReason"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.timeline-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  background: rgb(var(--surface-1));
  overflow-y: auto;
  overflow-x: auto;
  container-type: inline-size;
  container-name: timelineArea;
}

.timeline-internal-wrapper {
  display: flex;
  flex-direction: column;
  min-width: 100%;
  width: max-content;
  position: relative;
}

.timeline-headers {
  display: flex;
  flex-direction: column;
  border-bottom: 1px solid rgb(var(--border-strong));
  background: rgb(var(--slate-2));
  min-width: 100%;
  box-sizing: border-box;
  position: sticky;
  top: 0;
  z-index: 40;
}

.timeline-headers-row {
  display: flex;
  align-items: stretch;
  width: 100%;
}

.border-bottom-strong {
  border-bottom: 1px solid rgb(var(--border-strong));
}

.time-header-spacer {
  width: 64px;
  flex-shrink: 0;
  text-align: center;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  border-right: 1px solid rgb(var(--border-strong));
  padding: 12px 0;
  box-sizing: border-box;
  position: sticky;
  left: 0;
  z-index: 10;
  background: rgb(var(--slate-2));
}

.timeline-day-header {
  flex: 1;
  text-align: center;
  padding: 12px 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  border-right: 1px solid rgb(var(--border-strong));
  box-sizing: border-box;
  min-width: var(--dynamic-col-width, 0px) !important;
  overflow: hidden;
  position: relative;
}

.header-locked-icon {
  position: absolute;
  top: 8px;
  right: 8px;
  color: rgb(var(--slate-8));
  font-size: 14px;
}

.day-str {
  @apply text-sm;
  text-transform: uppercase;
  font-weight: 600;
  color: rgb(var(--slate-10));
}

/* Weekends styled in red — matches the reference visual language */
.timeline-day-header.is-weekend .day-str,
.timeline-day-header.is-weekend .day-num:not(.today) {
  color: #dc2626;
}

.day-num-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
}

.day-num {
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
}

.day-num.today {
  background: #3b82f6;
  color: #fff;
}

.header-day-blocks {
  display: flex;
  flex-direction: column;
  gap: 2px;
  width: 100%;
  padding: 0 4px;
  margin-top: 4px;
  box-sizing: border-box;
}

.day-view-blocks-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 2px;
  padding: 4px;
}

.header-block-banner {
  @apply text-sm;
  font-weight: 600;
  padding: 3px 6px;
  border-radius: 4px;
  color: #fff;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: center;
}

.block-type-holiday {
  background: #10b981;
}

.block-type-holiday.is-past {
  background: rgba(16, 185, 129, 0.35);
  color: rgba(6, 95, 70, 0.9);
}

.block-type-exception {
  background: #f59e0b;
}

.block-type-exception.is-past {
  background: rgba(245, 158, 11, 0.35);
  color: rgba(146, 64, 14, 0.9);
}

.block-type-closed {
  background: #9ca3af;
}

.block-type-closed.is-past {
  background: rgba(156, 163, 175, 0.35);
  color: rgba(55, 65, 81, 0.9);
}

.dark .block-type-holiday { background: rgba(16, 185, 129, 0.85); color: #fff; }
.dark .block-type-holiday.is-past { background: rgba(16, 185, 129, 0.25); color: rgba(16, 185, 129, 0.9); }
.dark .block-type-exception { background: rgba(245, 158, 11, 0.85); color: #fff; }
.dark .block-type-exception.is-past { background: rgba(245, 158, 11, 0.25); color: rgba(251, 191, 36, 0.9); }
.dark .block-type-closed { background: rgba(100, 116, 139, 0.5); color: rgba(241, 245, 249, 0.9); }
.dark .block-type-closed.is-past { background: rgba(100, 116, 139, 0.25); color: rgba(148, 163, 184, 0.8); }

.agent-header {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
}

.agent-color-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
}

.agent-name-label {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}

.timeline-grid-wrapper {
  position: relative;
  min-width: 100%;
}

.timeline-grid-background {
  display: flex;
  flex-direction: column;
}

.timeline-row {
  display: flex;
  border-bottom: 1px solid rgb(var(--border-strong));
  position: relative;
}

.time-label {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 64px;
  flex-shrink: 0;
  border-right: 1px solid rgb(var(--border-strong));
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  box-sizing: border-box;
  position: sticky;
  left: 0;
  z-index: 10;
  background: rgb(var(--surface-1));
}

.timeline-cell {
  flex: 1;
  border-right: 1px solid rgb(var(--border-strong));
  position: relative;
  cursor: pointer;
  padding: 4px;
  box-sizing: border-box;
  min-width: 0;
}

.timeline-cell {
  transition: background 0.15s ease-in-out;
}

.timeline-cell:hover {
  background: rgba(59, 130, 246, 0.10);
}

/* Agent column wash (day view) — usa CSS variable setada via inline style
   no template; o hover acima ainda funciona porque a regra de classe perde
   pra :hover (mesma specificity, mas :hover vem depois na cascade). */
.timeline-cell.cell-agent-tinted {
  background: var(--agent-tint, transparent);
}
.timeline-cell.cell-agent-tinted:hover {
  background: rgba(59, 130, 246, 0.10);
}

/* Blocked slot — diagonal hatch differentiates closed/past/lunch/holiday from
   normal slots. Uses solid slate-2/slate-4 tokens (same recipe as the modal's
   blocked slot button) so the pattern actually renders — the previous
   `rgba(var(--slate-12), 0.04)` mix of modern + legacy syntax is invalid and
   the gradient was being silently dropped by the parser. */
.timeline-cell.cell-blocked {
  cursor: not-allowed;
  background: repeating-linear-gradient(
    -45deg,
    rgb(var(--slate-2)),
    rgb(var(--slate-2)) 7px,
    rgb(var(--slate-3)) 7px,
    rgb(var(--slate-3)) 9px
  ) !important;
  position: relative;
}

.timeline-cell.cell-blocked:hover {
  background: repeating-linear-gradient(
    -45deg,
    rgb(var(--slate-2)),
    rgb(var(--slate-2)) 7px,
    rgb(var(--slate-4)) 7px,
    rgb(var(--slate-4)) 9px
  ) !important;
}

.blocked-slot-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: row;
  gap: 6px;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}

.blocked-slot-icon {
  width: 12px;
  height: 12px;
  color: rgb(var(--slate-8));
}

/* Tooltip moderno do slot bloqueado — aparece em hover do cell.
   Hover é detectado no .timeline-cell (overlay tem pointer-events:none e
   passa eventos pra trás). z-index alto + lift do cell pai pra escapar do
   stacking context da events-layer (z-index: 5). */
.blocked-slot-tooltip {
  position: absolute;
  top: calc(100% + 8px);
  left: 50%;
  transform: translateX(-50%);
  padding: 6px 10px;
  background: rgb(31, 41, 55);
  color: #fff;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 500;
  white-space: nowrap;
  letter-spacing: 0.01em;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.15s ease-in-out, transform 0.15s ease-in-out;
  z-index: 100;
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.18), 0 1px 3px rgba(0, 0, 0, 0.12);
}

.blocked-slot-tooltip::after {
  content: '';
  position: absolute;
  bottom: 100%;
  left: 50%;
  transform: translateX(-50%);
  border: 5px solid transparent;
  border-bottom-color: rgb(31, 41, 55);
}

/* Eleva a célula bloqueada hovered acima da events-layer pra que o tooltip
   não seja escondido. cell-blocked não tem nada da events-layer em cima
   visualmente (lanes pulam slots bloqueados), então o lift não esconde
   conteúdo relevante. */
.timeline-cell.cell-blocked:hover {
  z-index: 50;
}

.timeline-cell.cell-blocked:hover .blocked-slot-tooltip {
  opacity: 1;
}

/* WL matched cells */
.cell-wl-match {
  background: rgba(34, 197, 94, 0.07) !important;
  position: relative;
}

.cell-wl-match::after {
  content: '';
  position: absolute;
  inset: 2px;
  border: 1px dashed rgba(34, 197, 94, 0.45);
  border-radius: 3px;
  pointer-events: none;
}

.wl-cell-actions {
  position: absolute;
  bottom: 4px;
  right: 4px;
  display: flex;
  gap: 4px;
  opacity: 0;
  transition: opacity 0.12s;
  z-index: 2;
}

.cell-wl-match:hover .wl-cell-actions {
  opacity: 1;
}

.wl-cell-btn {
  width: 28px;
  height: 28px;
  border: none;
  border-radius: 6px;
  background: rgba(34, 197, 94, 0.18);
  color: rgba(34, 197, 94, 0.9);
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-sm;
  cursor: pointer;
  transition: background 0.12s, color 0.12s, transform 0.1s;
}

.wl-cell-btn:hover {
  background: rgba(34, 197, 94, 0.28);
  color: rgba(34, 197, 94, 1);
  transform: scale(1.1);
}

.wl-cell-btn--wl {
  background: rgba(99, 102, 241, 0.15);
  color: rgba(99, 102, 241, 0.85);
}

.wl-cell-btn--wl:hover {
  background: rgba(99, 102, 241, 0.28);
  color: rgba(99, 102, 241, 1);
}

/* Events overlay */
.timeline-events-layer {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  pointer-events: none;
  z-index: 5;
}

.day-events-column {
  flex: 1;
  position: relative;
  /* height set inline as dayHours.length × rowHeight so the events layer
     matches the grid background exactly (it shrinks when show_only_working_hours
     is on, instead of leaving a hardcoded 24h gap). */
  border-right: 1px solid transparent;
  min-width: var(--dynamic-col-width, 0px) !important;
}

/* Lane do agente em week view — faixa pastel atrás dos cards. Top/height
   são definidos inline via segmentos. A identificação visual do agente
   (linha colorida na cor sólida) vive no day header em `.day-header-agent-stripe`,
   não na lane. Sem pointer-events pra não interferir com cliques nos cards.
   z-index: 0 mantém abaixo dos eventos (z-index 5+). */
.agent-lane-bg {
  position: absolute;
  pointer-events: none;
  z-index: 0;
}

/* Faixas coloridas dos agentes na borda inferior do day header (week view).
   Mesma proporção das lanes abaixo, criando alinhamento visual "linha
   colorida → lane do agente". */
.day-header-agent-stripes {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  height: 3px;
  pointer-events: none;
}

.day-header-agent-stripe {
  position: absolute;
  top: 0;
  bottom: 0;
}

.time-label-spacer {
  width: 64px;
  flex-shrink: 0;
  box-sizing: border-box;
  position: sticky;
  left: 0;
  z-index: 10;
}

.current-time-line {
  position: absolute;
  left: 64px;
  right: 0;
  height: 2px;
  background-color: rgb(var(--blue-9));
  z-index: 20;
  pointer-events: none;
}

.current-time-dot {
  position: absolute;
  left: -4px;
  top: -4px;
  width: 10px;
  height: 10px;
  background-color: rgb(var(--blue-9));
  border-radius: 50%;
}

</style>
