import { parseEventDate, toLocalDatetimeString } from '../utils/agenda-date.js';

export function useAgendaDnD({ agenda, store, timelineAreaRef }) {
  const initDrag = ({ event, $event }) => {
    if ($event.button !== 0) return;
    
    const actionable = ['scheduled', 'confirmed'];
    if (!actionable.includes(event.status)) return;
    
    const start = parseEventDate(event.starts_at);
    const now = agenda.state.now || new Date();
    if (start < now) return;

    const { state } = agenda;
    state.isDragging = true;
    state.draggingEvent = { ...event };
    state.draggingEventId = event.id;
    state.draggingOriginalStartsAt = event.starts_at;
    state.draggingOriginalEndsAt = event.ends_at;
    state.dragCurrentStartsAt = event.starts_at;
    state.dragCurrentEndsAt = event.ends_at;
    state.dragStartX = $event.clientX;
    state.dragStartY = $event.clientY;
    state.dragHasMoved = false;

    const startDate = parseEventDate(event.starts_at);
    const evtRect = $event.target.getBoundingClientRect();
    state.dragClickOffsetPx = $event.clientY - evtRect.top;

    const dayObj = {
      day: startDate.getDate(),
      month: startDate.getMonth(),
      year: startDate.getFullYear(),
    };
    state.dragCurrentDayObj = dayObj;
  };

  const initResize = ({ event, $event }) => {
    if ($event.button !== 0) return;
    
    const actionable = ['scheduled', 'confirmed'];
    if (!actionable.includes(event.status)) return;
    
    const end = parseEventDate(event.ends_at);
    const now = agenda.state.now || new Date();
    if (end < now) return;

    $event.preventDefault();
    const { state } = agenda;
    state.isResizing = true;
    state.resizingEvent = event;
    state.resizingEventId = event.id;
    state.initialMouseY = $event.clientY;
    state.initialEndMs = parseEventDate(event.ends_at).getTime();
    state.resizingEventEndAt = event.ends_at;
  };

  const onGlobalMouseMove = (e) => {
    const { state } = agenda;
    const pph = agenda.pixelsPerHour.value;

    // Drag
    if (state.isDragging && state.draggingEvent) {
      const dx = Math.abs(e.clientX - state.dragStartX);
      const dy = Math.abs(e.clientY - state.dragStartY);
      if (!state.dragHasMoved && (dx > 4 || dy > 4)) {
        state.dragHasMoved = true;
      }
      if (!state.dragHasMoved) return;

      const timelineEl = timelineAreaRef.value?.$el;
      if (!timelineEl) return;
      const scrollTop = timelineEl.scrollTop || 0;
      const rect = timelineEl.getBoundingClientRect();
      const yInTimeline = e.clientY - rect.top + scrollTop - state.dragClickOffsetPx;
      const totalMinutes = (yInTimeline / pph) * 60;
      const snapped = Math.round(totalMinutes / 5) * 5;
      const newH = Math.floor(snapped / 60);
      const newM = snapped % 60;

      const startDate = parseEventDate(state.draggingOriginalStartsAt);
      const endDate = parseEventDate(state.draggingOriginalEndsAt);
      const durationMs = endDate.getTime() - startDate.getTime();

      const newStartDate = new Date(state.dragCurrentDayObj.year, state.dragCurrentDayObj.month, state.dragCurrentDayObj.day, newH, newM);
      const newEndDate = new Date(newStartDate.getTime() + durationMs);

      state.dragCurrentStartsAt = toLocalDatetimeString(newStartDate);
      state.dragCurrentEndsAt = toLocalDatetimeString(newEndDate);
    }

    // Resize
    if (state.isResizing && state.resizingEvent) {
      const dy = e.clientY - state.initialMouseY;
      const minutesDelta = (dy / pph) * 60;
      const snapped = Math.round(minutesDelta / 5) * 5;
      const newEndMs = state.initialEndMs + snapped * 60000;
      const minEndMs = parseEventDate(state.resizingEvent.starts_at).getTime() + 5 * 60000;
      const finalMs = Math.max(newEndMs, minEndMs);
      state.resizingEventEndAt = toLocalDatetimeString(new Date(finalMs));
    }
  };

  const onGlobalMouseUp = async () => {
    const { state } = agenda;

    // Drag end
    if (state.isDragging && state.dragHasMoved && state.draggingEvent) {
      state.skipNextClick = true;
      try {
        await store.dispatch('agendaEvents/update', {
          id: state.draggingEventId,
          agenda_event: {
            starts_at: state.dragCurrentStartsAt,
            ends_at: state.dragCurrentEndsAt,
          },
        });
      } catch {
        // ignore
      }
    }
    state.isDragging = false;
    state.draggingEvent = null;
    state.draggingEventId = null;
    state.dragHasMoved = false;

    // Resize end
    if (state.isResizing && state.resizingEvent) {
      state.skipNextClick = true;
      try {
        await store.dispatch('agendaEvents/update', {
          id: state.resizingEventId,
          agenda_event: {
            ends_at: state.resizingEventEndAt,
          },
        });
      } catch {
        // ignore
      }
    }
    state.isResizing = false;
    state.resizingEvent = null;
    state.resizingEventId = null;
    state.resizingEventEndAt = null;
  };

  return {
    initDrag,
    initResize,
    onGlobalMouseMove,
    onGlobalMouseUp,
  };
}
