/**
 * useAgenda — Estado centralizado do módulo de Agenda.
 *
 * Módulo singleton reativo usando Vue.reactive() que pode ser consumido
 * tanto por componentes Options API (via mixin/inject) quanto diretamente.
 */
import { reactive, computed } from 'vue';
import { MONTH_KEYS, DAY_KEYS, DOW_MAP, STATUS_CONFIGS } from '../utils/agenda-constants.js';
import { agentIdToColor, solidEventBg } from '../utils/agenda-colors.js';
import { padZ, parseEventDate, formatEventTime, toLocalDatetimeString } from '../utils/agenda-date.js';

/**
 * Cria uma instância do estado da Agenda.
 * Chamado uma única vez pelo AgendaDashboard e disponibilizado via provide/inject.
 */
export function createAgendaState() {
  const state = reactive({
    // ─── Navegação ──────────────────────────────────────
    currentDate: new Date(),
    viewMode: 'month',
    layoutMode: 'side-by-side',

    // ─── Tema & Responsividade ─────────────────────────
    isDarkTheme: document.body.classList.contains('dark'),
    windowWidth: typeof window !== 'undefined' ? window.innerWidth : 1024,

    // ─── UI Toggles ────────────────────────────────────
    showSummaryBar: false,
    showMobileSidebar: false,
    viewDropdownOpen: false,

    // ─── Filtros ────────────────────────────────────────
    expandedFilters: {
      agents: true,
      priority: false,
      eventType: false,
      treatments: false,
      waitingList: false,
    },
    hiddenAgents: [],
    hiddenPriorities: [],
    hiddenEventTypes: [],
    hiddenTreatments: [],

    // ─── Modal de Evento ───────────────────────────────
    showNewEventModal: false,
    isEditing: false,
    editingEventId: null,
    isSaving: false,

    // ─── Modal de Exclusão ─────────────────────────────
    showConfirmDelete: false,
    deleteReason: '',
    deleteReasonNote: '',
    isDeleting: false,

    // ─── Resize ────────────────────────────────────────
    isResizing: false,
    resizingEvent: null,
    resizingEventId: null,
    resizingEventEndAt: null,
    initialMouseY: 0,
    initialEndMs: 0,

    // ─── Drag-and-drop ─────────────────────────────────
    isDragging: false,
    draggingEvent: null,
    draggingEventId: null,
    draggingOriginalStartsAt: null,
    draggingOriginalEndsAt: null,
    dragCurrentStartsAt: null,
    dragCurrentEndsAt: null,
    dragCurrentDayObj: null,
    dragHasMoved: false,
    dragStartX: 0,
    dragStartY: 0,
    dragClickOffsetPx: 0,

    // ─── Popups ────────────────────────────────────────
    eventInfoPopup: null,
    statusUpdatingId: null,
    wlInfoPopup: null,
    wlCellPopup: null,
    showWlScheduleModal: false,
    wlScheduleEntry: null,

    // ─── Skip Click ────────────────────────────────────
    skipNextClick: false,

    // ─── Timer ─────────────────────────────────────────
    now: new Date(),

    // ─── Configurações carregadas ──────────────────────
    agendaSettingsData: null,
    customAttributesConfig: [],
  });

  // ─── Internals ──────────────────────────────────────
  let _timer = null;
  let _themeObserver = null;
  let _handleResize = null;

  // ─── Computed derivados ─────────────────────────────

  const isMobile = computed(() => state.windowWidth < 768);

  const agendaSettings = computed(() => state.agendaSettingsData);

  const rowHeight = computed(() => {
    const interval = agendaSettings.value?.slot_interval_minutes || 60;
    return (interval / 60) * 80;
  });

  const pixelsPerHour = computed(() => {
    const interval = agendaSettings.value?.slot_interval_minutes || 60;
    return rowHeight.value * (60 / interval);
  });

  const dayHours = computed(() => {
    const hours = [];
    const interval = agendaSettings.value?.slot_interval_minutes || 60;
    const slotsPerHour = 60 / interval;
    for (let h = 0; h < 24; h += 1) {
      for (let s = 0; s < slotsPerHour; s += 1) {
        const minutes = s * interval;
        hours.push(`${padZ(h)}:${padZ(minutes)}`);
      }
    }
    return hours;
  });

  const currentMonth = computed(() => state.currentDate.getMonth());
  const currentYear = computed(() => state.currentDate.getFullYear());

  const today = computed(() => {
    const n = new Date();
    return { day: n.getDate(), month: n.getMonth(), year: n.getFullYear() };
  });

  const calendarDays = computed(() => {
    const year = currentYear.value;
    const month = currentMonth.value;
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    const startDow = firstDay.getDay();
    const totalDays = lastDay.getDate();
    const prevLast = new Date(year, month, 0).getDate();
    const days = [];

    for (let i = startDow - 1; i >= 0; i -= 1) {
      days.push({
        day: prevLast - i,
        month: month - 1,
        year: month === 0 ? year - 1 : year,
        isCurrentMonth: false,
      });
    }
    for (let d = 1; d <= totalDays; d += 1) {
      days.push({ day: d, month, year, isCurrentMonth: true });
    }
    const remaining = 42 - days.length;
    for (let i = 1; i <= remaining; i += 1) {
      days.push({
        day: i,
        month: month + 1,
        year: month === 11 ? year + 1 : year,
        isCurrentMonth: false,
      });
    }
    return days;
  });

  const calendarWeeks = computed(() => {
    const weeks = [];
    for (let i = 0; i < calendarDays.value.length; i += 7) {
      weeks.push(calendarDays.value.slice(i, i + 7));
    }
    return weeks;
  });

  const currentTimeLineStyle = computed(() => {
    const hours = state.now.getHours();
    const minutes = state.now.getMinutes();
    const top =
      hours * pixelsPerHour.value +
      (minutes / 60) * pixelsPerHour.value;
    return { top: `${top}px` };
  });

  const dragGhostStyle = computed(() => {
    if (
      !state.isDragging ||
      !state.dragCurrentStartsAt ||
      !state.dragCurrentEndsAt
    )
      return {};
    const start = parseEventDate(state.dragCurrentStartsAt);
    const end = parseEventDate(state.dragCurrentEndsAt);
    const topOffset =
      start.getHours() * pixelsPerHour.value +
      (start.getMinutes() / 60) * pixelsPerHour.value;
    const durationHours = Math.max(
      0.5,
      (end.getTime() - start.getTime()) / (1000 * 60 * 60)
    );
    return {
      position: 'absolute',
      top: `${topOffset + 2}px`,
      height: `${durationHours * pixelsPerHour.value - 4}px`,
      left: '3px',
      right: '3px',
      zIndex: 100,
      pointerEvents: 'none',
    };
  });

  // ─── Helpers (funções) ──────────────────────────────

  function isToday(dayObj) {
    return (
      dayObj.day === today.value.day &&
      dayObj.month === today.value.month &&
      dayObj.year === today.value.year
    );
  }

  function isSelectedDate(dayObj) {
    return (
      dayObj.day === state.currentDate.getDate() &&
      dayObj.month === state.currentDate.getMonth() &&
      dayObj.year === state.currentDate.getFullYear()
    );
  }

  function getDayHeaders(i18n) {
    return DAY_KEYS.map(k => i18n(`AGENDA.DAYS.${k}`));
  }

  function getMiniDayHeaders(i18n) {
    return DAY_KEYS.map(k => i18n(`AGENDA.DAYS.${k}`).charAt(0));
  }

  function getMonthLabel(i18n) {
    if (state.viewMode === 'day') {
      const d = state.currentDate;
      const dayKey = DAY_KEYS[d.getDay()];
      const monthKey = MONTH_KEYS[d.getMonth()];
      const dayLabel = i18n(`AGENDA.DAYS.${dayKey}`);
      const monthLabel = i18n(`AGENDA.MONTHS.${monthKey}`);
      return `${dayLabel}, ${d.getDate()} ${i18n('AGENDA.OF')} ${monthLabel} ${d.getFullYear()}`;
    }
    if (state.viewMode === 'week') {
      const week = getCurrentWeekDays(i18n);
      if (week && week.length === 7) {
        const first = week[0];
        const last = week[6];
        const monthKey = MONTH_KEYS[first.month];
        const monthLabel = i18n(`AGENDA.MONTHS.${monthKey}`);
        if (first.month === last.month) {
          return `${first.day} – ${last.day} ${i18n('AGENDA.OF')} ${monthLabel} ${first.year}`;
        }
        return `${first.day}/${first.month + 1} – ${last.day}/${last.month + 1} ${last.year}`;
      }
    }
    const key = MONTH_KEYS[currentMonth.value];
    return `${i18n(`AGENDA.MONTHS.${key}`)} ${i18n('AGENDA.OF')} ${currentYear.value}`;
  }

  function getCurrentWeekDays(i18n) {
    const headers = getDayHeaders(i18n);
    const target = {
      day: state.currentDate.getDate(),
      month: state.currentDate.getMonth(),
      year: state.currentDate.getFullYear(),
    };
    for (let i = 0; i < calendarWeeks.value.length; i += 1) {
      const week = calendarWeeks.value[i];
      if (
        week.find(
          w =>
            w.day === target.day &&
            w.month === target.month &&
            w.year === target.year
        )
      ) {
        return week.map((w, idx) => ({ ...w, label: headers[idx] }));
      }
    }
    return [];
  }

  function getCurrentDayObj(i18n) {
    const headers = getDayHeaders(i18n);
    const dayIdx = state.currentDate.getDay();
    return {
      day: state.currentDate.getDate(),
      month: state.currentDate.getMonth(),
      year: state.currentDate.getFullYear(),
      label: headers[dayIdx],
    };
  }

  // ─── Navegação ──────────────────────────────────────

  function prevPeriod() {
    const d = new Date(state.currentDate);
    if (state.viewMode === 'day') {
      d.setDate(d.getDate() - 1);
    } else if (state.viewMode === 'week') {
      d.setDate(d.getDate() - 7);
    } else {
      d.setMonth(d.getMonth() - 1);
    }
    state.currentDate = d;
  }

  function nextPeriod() {
    const d = new Date(state.currentDate);
    if (state.viewMode === 'day') {
      d.setDate(d.getDate() + 1);
    } else if (state.viewMode === 'week') {
      d.setDate(d.getDate() + 7);
    } else {
      d.setMonth(d.getMonth() + 1);
    }
    state.currentDate = d;
  }

  function goToToday() {
    state.currentDate = new Date();
  }

  function setViewMode(mode) {
    state.viewMode = mode;
  }

  function handleMiniCalendarClick(dayObj) {
    state.currentDate = new Date(dayObj.year, dayObj.month, dayObj.day);
  }

  // ─── Filtros ────────────────────────────────────────

  function toggleFilter(key) {
    state.expandedFilters[key] = !state.expandedFilters[key];
  }

  function toggleAgent(id) {
    const idx = state.hiddenAgents.indexOf(id);
    if (idx >= 0) state.hiddenAgents.splice(idx, 1);
    else state.hiddenAgents.push(id);
  }

  function togglePriority(val) {
    const idx = state.hiddenPriorities.indexOf(val);
    if (idx >= 0) state.hiddenPriorities.splice(idx, 1);
    else state.hiddenPriorities.push(val);
  }

  function toggleEventType(val) {
    const idx = state.hiddenEventTypes.indexOf(val);
    if (idx >= 0) state.hiddenEventTypes.splice(idx, 1);
    else state.hiddenEventTypes.push(val);
  }

  function toggleTreatment(val) {
    const idx = state.hiddenTreatments.indexOf(val);
    if (idx >= 0) state.hiddenTreatments.splice(idx, 1);
    else state.hiddenTreatments.push(val);
  }

  // ─── Agentes ────────────────────────────────────────

  function buildAgentList(agents) {
    if (agents && agents.length) {
      return agents.map(a => ({
        ...a,
        color: agentIdToColor(a.id),
      }));
    }
    return [
      { id: 1, name: 'Rafael', color: agentIdToColor(1) },
      { id: 2, name: 'Juliana', color: agentIdToColor(2) },
      { id: 3, name: 'Gabi', color: agentIdToColor(3) },
      { id: 4, name: 'Leandro', color: agentIdToColor(4) },
    ];
  }

  function getActiveAgents(agentList, isAdmin, currentUserID) {
    if (isAdmin) {
      return agentList.filter(a => !state.hiddenAgents.includes(a.id));
    }
    return agentList.filter(a => a.id === currentUserID);
  }

  function getVisibleAgentList(agentList, isAdmin, currentUserID) {
    if (isAdmin) return agentList;
    return agentList.filter(a => a.id === currentUserID);
  }

  // ─── Eventos ────────────────────────────────────────

  function getTreatmentColor(event, treatmentOptions) {
    if (!treatmentOptions || !treatmentOptions.length) return null;
    const tName = event.custom_attributes?.treatment;
    if (!tName) return null;
    const matched = treatmentOptions.find(t => t.name === tName);
    return matched ? matched.color : null;
  }

  function getAgentColor(event, agentList, currentUserID, treatmentOptions) {
    if (event && event.color) return event.color;

    const uid = event && event.user_id ? event.user_id : currentUserID;
    const agent = agentList.find(a => a.id === uid);
    return agent ? agent.color : agentIdToColor(uid || 1);
  }

  function getEventBackground(event, agentList, currentUserID, treatmentOptions) {
    return solidEventBg(
      getAgentColor(event, agentList, currentUserID, treatmentOptions),
      state.isDarkTheme
    );
  }

  function getEventsForDay(dayObj, agendaEvents, isAdmin, currentUserID, treatmentOptions) {
    if (!agendaEvents || !agendaEvents.length) return [];

    const events = agendaEvents.filter(e => {
      if (!isAdmin && e.user_id !== currentUserID) return false;
      if (state.hiddenAgents.includes(e.user_id)) return false;

      const eventPriority = e.custom_attributes?.priority || 'medium';
      if (state.hiddenPriorities.includes(eventPriority)) return false;

      const evType = e.event_type || 'consultation';
      if (state.hiddenEventTypes.includes(evType)) return false;

      const eventTreatment = e.custom_attributes?.treatment;
      if (eventTreatment && state.hiddenTreatments.includes(eventTreatment))
        return false;

      const d = parseEventDate(e.starts_at || e.start_time);
      return (
        d.getDate() === dayObj.day &&
        d.getMonth() === dayObj.month &&
        d.getFullYear() === dayObj.year
      );
    });
    return [...events].sort((a, b) => {
      const da = parseEventDate(a.starts_at || a.start_time);
      const db = parseEventDate(b.starts_at || b.start_time);
      return da - db;
    });
  }

  function areOverlapping(a, b) {
    const startA = parseEventDate(a.starts_at).getTime();
    const endA = parseEventDate(a.ends_at).getTime();
    const startB = parseEventDate(b.starts_at).getTime();
    const endB = parseEventDate(b.ends_at).getTime();
    return startA < endB && startB < endA;
  }

  function calculateOverlaps(events) {
    if (!events || !events.length) return [];

    const sorted = [...events].sort((a, b) => {
      return parseEventDate(a.starts_at) - parseEventDate(b.starts_at);
    });

    const clusters = [];
    let currentCluster = [];
    let maxEnd = 0;

    sorted.forEach(event => {
      const start = parseEventDate(event.starts_at).getTime();
      const end = parseEventDate(event.ends_at).getTime();

      if (currentCluster.length > 0 && start >= maxEnd) {
        clusters.push(currentCluster);
        currentCluster = [];
        maxEnd = 0;
      }

      currentCluster.push(event);
      if (end > maxEnd) maxEnd = end;
    });
    if (currentCluster.length > 0) clusters.push(currentCluster);

    const result = [];
    clusters.forEach(cluster => {
      const columns = [];
      cluster.forEach(event => {
        let colIdx = 0;
        while (
          columns[colIdx] &&
          columns[colIdx].some(e => areOverlapping(e, event))
        ) {
          colIdx++;
        }
        if (!columns[colIdx]) columns[colIdx] = [];
        columns[colIdx].push(event);
        event.tempCol = colIdx;
      });

      const totalCols = columns.length;
      cluster.forEach(event => {
        result.push({
          ...event,
          colIdx: event.tempCol,
          totalCols,
        });
      });
    });

    return result;
  }

  function getStatusConfig(status) {
    return STATUS_CONFIGS[status] || STATUS_CONFIGS.scheduled;
  }

  function isEventLate(event) {
    const actionable = ['scheduled', 'confirmed'];
    if (!actionable.includes(event.status)) return false;
    if (!event.starts_at) return false;
    const start = parseEventDate(event.starts_at);
    const diffMs = state.now - start;
    return diffMs >= 5 * 60 * 1000;
  }

  // ─── Bloqueio de horários e dias ───────────────────────────

  function isDayInPast(dayObj) {
    if (!dayObj) return false;
    const now = state.now || new Date();
    const current = new Date(dayObj.year, dayObj.month, dayObj.day, 23, 59, 59, 999);
    return current < now;
  }

  function isDayBlocked(dayObj) {
    const settings = agendaSettings.value;
    if (!settings) return false;
    
    const dayDate = new Date(dayObj.year, dayObj.month, dayObj.day);
    const dow = dayDate.getDay();
    const dayId = DOW_MAP[dow];
    const dayConfig = settings.week_days && settings.week_days.find(d => d.id === dayId);
    
    if (settings.block_outside_working_hours) {
      if (!dayConfig || !dayConfig.enabled) return 'Fechado';
    }

    if (settings.holidays && settings.holidays.length) {
      const padZ2 = n => String(n).padStart(2, '0');
      const dayFormatted = `${padZ2(dayDate.getDate())}/${padZ2(dayDate.getMonth() + 1)}/${dayDate.getFullYear()}`;
      const matchedHoliday = settings.holidays.find(hol => {
        if (hol.status !== 'closed') return false;
        const holDayMonth = hol.date.slice(0, 5);
        const targetDayMonth = dayFormatted.slice(0, 5);
        return holDayMonth === targetDayMonth;
      });
      if (matchedHoliday) return matchedHoliday.title || 'Feriado';
    }

    if (settings.exceptions && settings.exceptions.length) {
      const dayTs = dayDate.getTime();
      const matchedEx = settings.exceptions.find(ex => {
        if (!ex.start || !ex.end) return false;
        const exStart = new Date(ex.start);
        const exEnd = new Date(ex.end);
        exStart.setHours(0, 0, 0, 0);
        exEnd.setHours(23, 59, 59, 999);
        return dayTs >= exStart.getTime() && dayTs <= exEnd.getTime();
      });
      if (matchedEx) return matchedEx.title || 'Folga / Exceção';
    }
    
    return false;
  }

  function isHourBlocked(dayObj, hourStr) {
    const settings = agendaSettings.value;
    if (!settings) return false;

    const dayDate = new Date(dayObj.year, dayObj.month, dayObj.day);
    const dow = dayDate.getDay();
    const dayId = DOW_MAP[dow];
    const dayConfig =
      settings.week_days && settings.week_days.find(d => d.id === dayId);

    const [h] = hourStr.split(':').map(Number);

    // 0. Passado
    const now = state.now || new Date();
    const m = Number(hourStr.split(':')[1] || 0);
    const cellTime = new Date(dayObj.year, dayObj.month, dayObj.day, h, m);
    if (cellTime < now) return 'Passado';

    // 1. Feriados
    if (settings.holidays && settings.holidays.length) {
      const padZ2 = n => String(n).padStart(2, '0');
      const dayFormatted = `${padZ2(dayDate.getDate())}/${padZ2(dayDate.getMonth() + 1)}/${dayDate.getFullYear()}`;
      const matchedHoliday = settings.holidays.find(hol => {
        if (hol.status !== 'closed') return false;
        const holDayMonth = hol.date.slice(0, 5);
        const targetDayMonth = dayFormatted.slice(0, 5);
        return holDayMonth === targetDayMonth;
      });
      if (matchedHoliday) return matchedHoliday.title || 'Feriado';
    }

    // 2. Exceções / Folgas
    if (settings.exceptions && settings.exceptions.length) {
      const dayTs = dayDate.getTime();
      const matchedEx = settings.exceptions.find(ex => {
        if (!ex.start || !ex.end) return false;
        const exStart = new Date(ex.start);
        const exEnd = new Date(ex.end);
        exStart.setHours(0, 0, 0, 0);
        exEnd.setHours(23, 59, 59, 999);
        return dayTs >= exStart.getTime() && dayTs <= exEnd.getTime();
      });
      if (matchedEx) return matchedEx.title || 'Folga / Exceção';
    }

    // 3. Fechado no dia (ex: Domingo)
    if (!dayConfig || !dayConfig.enabled) return 'Fechado';

    // 4. Fora do horário de funcionamento
    if (settings.block_outside_working_hours) {
      if (dayConfig.start && dayConfig.end) {
        const openH = Number(dayConfig.start.split(':')[0]);
        const closeH = Number(dayConfig.end.split(':')[0]);
        if (h < openH || h >= closeH) return 'Fora do expediente';
      }
    }

    // 4. Horário de almoço
    if (settings.block_lunch_break && dayConfig && dayConfig.enabled) {
      if (dayConfig.lunchStart && dayConfig.lunchEnd) {
        const lunchStartH = Number(dayConfig.lunchStart.split(':')[0]);
        const lunchEndH = Number(dayConfig.lunchEnd.split(':')[0]);
        if (h >= lunchStartH && h < lunchEndH) return 'Almoço';
      }
    }

    return false;
  }

  function getBlockedMessage(dayObj, hourStr, useAlertFn) {
    const [h, m] = hourStr.split(':').map(Number);
    const now = state.now || new Date();
    const cellTime = new Date(dayObj.year, dayObj.month, dayObj.day, h, m || 0);
    if (cellTime < now) {
      useAlertFn('Não é possível criar agendamentos no passado.');
      return true;
    }

    const settings = agendaSettings.value;
    const dayDate = new Date(dayObj.year, dayObj.month, dayObj.day);
    const dow = dayDate.getDay();
    const dayConfig =
      settings &&
      settings.week_days &&
      settings.week_days.find(d => d.id === DOW_MAP[dow]);

    // Feriado
    if (settings && settings.holidays && settings.holidays.length) {
      const padZ2 = n => String(n).padStart(2, '0');
      const dayFormatted = `${padZ2(dayDate.getDate())}/${padZ2(dayDate.getMonth() + 1)}/${dayDate.getFullYear()}`;
      const matchedHoliday = settings.holidays.find(hol => {
        if (hol.status !== 'closed') return false;
        return hol.date.slice(0, 5) === dayFormatted.slice(0, 5);
      });
      if (matchedHoliday) {
        useAlertFn(
          `Este dia é feriado (${matchedHoliday.name}) e está configurado como fechado.`
        );
        return true;
      }
    }

    // Exceção/Folga
    if (settings && settings.exceptions && settings.exceptions.length) {
      const dayTs = dayDate.getTime();
      const matchedEx = settings.exceptions.find(ex => {
        if (!ex.start || !ex.end) return false;
        const exStart = new Date(ex.start);
        const exEnd = new Date(ex.end);
        exStart.setHours(0, 0, 0, 0);
        exEnd.setHours(23, 59, 59, 999);
        return dayTs >= exStart.getTime() && dayTs <= exEnd.getTime();
      });
      if (matchedEx) {
        useAlertFn(
          `Este dia está bloqueado por uma folga/exceção: "${matchedEx.title}".`
        );
        return true;
      }
    }

    let msg = 'Este horário está bloqueado para agendamentos.';
    if (
      dayConfig &&
      dayConfig.enabled &&
      dayConfig.start &&
      dayConfig.end
    ) {
      msg = `Este horário está bloqueado. Por favor, tente um horário de funcionamento entre ${dayConfig.start} e ${dayConfig.end}.`;
    } else if (dayConfig && !dayConfig.enabled) {
      msg = `Este dia da semana está configurado como Fechado.`;
    }

    useAlertFn(msg);
    return true;
  }

  function getDayBlockInfo(dayObj) {
    const settings = agendaSettings.value;
    if (!settings) return [];
    const blocks = [];
    
    const dayDate = new Date(dayObj.year, dayObj.month, dayObj.day);
    const dayTs = dayDate.getTime();
    const todayTs = new Date();
    todayTs.setHours(0, 0, 0, 0);
    const isPast = dayTs < todayTs.getTime();
    
    // Feriados
    if (settings.holidays && settings.holidays.length) {
      const padZ2 = n => String(n).padStart(2, '0');
      const dayFormatted = `${padZ2(dayDate.getDate())}/${padZ2(dayDate.getMonth() + 1)}/${dayDate.getFullYear()}`;
      settings.holidays.forEach(hol => {
        if (hol.status !== 'closed') return;
        const holDayMonth = hol.date.slice(0, 5);
        const targetDayMonth = dayFormatted.slice(0, 5);
        if (holDayMonth === targetDayMonth) {
          blocks.push({ type: 'holiday', title: hol.name || 'Feriado', isPast });
        }
      });
    }

    // Exceções / Folgas
    if (settings.exceptions && settings.exceptions.length) {
      settings.exceptions.forEach(ex => {
        if (!ex.start || !ex.end) return;
        const exStart = new Date(ex.start);
        const exEnd = new Date(ex.end);
        exStart.setHours(0, 0, 0, 0);
        exEnd.setHours(23, 59, 59, 999);
        if (dayTs >= exStart.getTime() && dayTs <= exEnd.getTime()) {
           blocks.push({ type: 'exception', title: ex.title || 'Folga / Exceção', isPast });
        }
      });
    }

    // Is the entire day closed based on weekDays?
    const dow = dayDate.getDay();
    const dayId = DOW_MAP[dow];
    const dayConfig = settings.week_days && settings.week_days.find(d => d.id === dayId);
    if (dayConfig && !dayConfig.enabled) {
      blocks.push({ type: 'closed', title: 'Fechado', isPast });
    }

    return blocks;
  }

  // ─── Waiting list match ─────────────────────────────

  function getWaitingListMatchForCell(dayObj, hourStr, waitingListEntries) {
    if (!waitingListEntries || !waitingListEntries.length) return [];
    const date = new Date(dayObj.year, dayObj.month, dayObj.day);
    const dayId = DOW_MAP[date.getDay()];
    const h = parseInt(hourStr.split(':')[0], 10);

    return waitingListEntries.filter(entry => {
      const days = entry.preferred_days || [];
      if (days.length && !days.includes(dayId)) return false;
      if (entry.period === 'morning' && (h < 6 || h >= 12)) return false;
      if (entry.period === 'afternoon' && (h < 12 || h >= 18)) return false;
      if (entry.period === 'evening' && (h < 18 || h >= 24)) return false;
      if (entry.specific_time) {
        const [sh] = entry.specific_time.split(':').map(Number);
        if (h !== sh) return false;
      }
      return true;
    });
  }

  // ─── Lifecycle ──────────────────────────────────────

  function init() {
    _handleResize = () => {
      state.windowWidth = window.innerWidth;
    };
    window.addEventListener('resize', _handleResize);

    _timer = setInterval(() => {
      state.now = new Date();
    }, 60000);

    _themeObserver = new MutationObserver(() => {
      state.isDarkTheme = document.body.classList.contains('dark');
    });
    _themeObserver.observe(document.body, {
      attributes: true,
      attributeFilter: ['class'],
    });
  }

  function destroy() {
    if (_handleResize) window.removeEventListener('resize', _handleResize);
    if (_timer) clearInterval(_timer);
    if (_themeObserver) _themeObserver.disconnect();
  }

  return {
    state,

    // Computed
    isMobile,
    agendaSettings,
    rowHeight,
    pixelsPerHour,
    dayHours,
    currentMonth,
    currentYear,
    today,
    calendarDays,
    calendarWeeks,
    currentTimeLineStyle,
    dragGhostStyle,

    // Helpers
    isToday,
    isSelectedDate,
    getDayHeaders,
    getMiniDayHeaders,
    getMonthLabel,
    getCurrentWeekDays,
    getCurrentDayObj,

    // Navigation
    prevPeriod,
    nextPeriod,
    goToToday,
    setViewMode,
    handleMiniCalendarClick,

    // Filters
    toggleFilter,
    toggleAgent,
    togglePriority,
    toggleEventType,
    toggleTreatment,

    // Agents
    buildAgentList,
    getActiveAgents,
    getVisibleAgentList,

    // Events
    getAgentColor,
    getEventBackground,
    getEventsForDay,
    calculateOverlaps,
    getStatusConfig,
    isEventLate,

    // Blocking
    isHourBlocked,
    isDayBlocked,
    isDayInPast,
    getBlockedMessage,
    getDayBlockInfo,

    // Waiting list
    getWaitingListMatchForCell,

    // Lifecycle
    init,
    destroy,
  };
}
