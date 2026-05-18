import { parseEventDate, toLocalDatetimeString } from '../utils/agenda-date.js';

const DRAG_THRESHOLD_PX = 5;

export function useAgendaDnD({ agenda, store, timelineAreaRef, currentWeekDays, activeAgents, onBlockedDrop }) {
  // Checks if any minute-precise slot covered by the proposed event falls on a
  // blocked range. Steps in 15-min increments so it respects working/lunch
  // boundaries that have non-zero minutes (e.g. closes at 12:30, lunch starts
  // at 11:30). The end boundary itself is exclusive — an event ending exactly
  // at close time is valid.
  function checkRangeBlocked(dayObj, startsAt, endsAt) {
    const start = parseEventDate(startsAt);
    const end = parseEventDate(endsAt);
    const startTotal = start.getHours() * 60 + start.getMinutes();
    const endTotal = end.getHours() * 60 + end.getMinutes();
    const STEP = 15;

    if (endTotal <= startTotal) {
      const hh = String(start.getHours()).padStart(2, '0');
      const mm = String(start.getMinutes()).padStart(2, '0');
      return agenda.isHourBlocked(dayObj, `${hh}:${mm}`) || false;
    }
    for (let t = startTotal; t < endTotal; t += STEP) {
      const hh = String(Math.floor(t / 60)).padStart(2, '0');
      const mm = String(t % 60).padStart(2, '0');
      const blocked = agenda.isHourBlocked(dayObj, `${hh}:${mm}`);
      if (blocked) return blocked;
    }
    return false;
  }

  // Returns the bounding rect of the events layer. Its `top` in viewport
  // coordinates corresponds to the FIRST visible hour (visibleStartHour),
  // which is 0 normally but shifts when show_only_working_hours is enabled.
  // Caller must add visibleStartHour*60 to map yInLayer-derived minutes back
  // to absolute clock time.
  function getEventsLayerRect() {
    const timelineEl = timelineAreaRef.value?.$el;
    if (!timelineEl) return null;
    const layer = timelineEl.querySelector('.timeline-events-layer');
    if (!layer) return null;
    return layer.getBoundingClientRect();
  }

  const initDrag = ({ event, $event }) => {
    if ($event.button !== 0) return;

    const actionable = ['scheduled', 'confirmed'];
    if (!actionable.includes(event.status)) return;

    const start = parseEventDate(event.starts_at);
    const now = agenda.state.nowMinute || new Date();
    if (start < now) return;

    const { state } = agenda;
    // ── ARM drag, but DON'T activate it yet ──
    // isDragging stays false until mouse moves past threshold. This way:
    // - Quick click → no drag visual, click event fires normally → opens popup
    // - Hold + move → threshold passed → drag activates
    state.dragArmed = true;
    state.isDragging = false;
    state.dragHasMoved = false;
    state.draggingEvent = { ...event };
    state.draggingEventId = event.id;
    state.draggingOriginalStartsAt = event.starts_at;
    state.draggingOriginalEndsAt = event.ends_at;
    state.dragCurrentStartsAt = event.starts_at;
    state.dragCurrentEndsAt = event.ends_at;
    state.dragStartX = $event.clientX;
    state.dragStartY = $event.clientY;
    state.dragIsBlocked = false;
    state.dragBlockReason = null;

    const startDate = parseEventDate(event.starts_at);
    const cardEl = $event.target.closest('.timeline-evt') || $event.target;
    const evtRect = cardEl.getBoundingClientRect();
    state.dragClickOffsetPx = $event.clientY - evtRect.top;

    state.dragCurrentDayObj = {
      day: startDate.getDate(),
      month: startDate.getMonth(),
      year: startDate.getFullYear(),
    };
  };

  const initResize = ({ event, $event }) => {
    if ($event.button !== 0) return;

    const actionable = ['scheduled', 'confirmed'];
    if (!actionable.includes(event.status)) return;

    const end = parseEventDate(event.ends_at);
    const now = agenda.state.nowMinute || new Date();
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
    // Snap drag/resize to the configured slot interval so the saved time
    // always lands on a grid line (15/30/60 min). The previous 5-min hard
    // snap produced off-grid times like 09:10 with 15-min slots.
    const snapMin = agenda.agendaSettings.value?.slot_interval_minutes || 60;

    // ── Drag (armed or already active) ──
    if (state.dragArmed || state.isDragging) {
      // Activate drag only after threshold is crossed
      if (!state.isDragging) {
        const dx = Math.abs(e.clientX - state.dragStartX);
        const dy = Math.abs(e.clientY - state.dragStartY);
        if (dx <= DRAG_THRESHOLD_PX && dy <= DRAG_THRESHOLD_PX) {
          return; // still inside the click hitbox — not a drag yet
        }
        state.isDragging = true;
        state.dragHasMoved = true;
      }

      // Use the events-layer rect: its top corresponds to time 0:00.
      // No need to subtract header height or scrollTop manually.
      const eventsRect = getEventsLayerRect();
      if (!eventsRect) return;

      const yInLayer = e.clientY - eventsRect.top - state.dragClickOffsetPx;
      // Coordinates are relative to the visible window. When show_only_working_hours
      // is on, the grid starts at visibleStartHour (e.g. 8h) — add it back to map
      // back to absolute clock time.
      const visibleStart = agenda.visibleStartHour.value || 0;
      const totalMinutes = (yInLayer / pph) * 60 + visibleStart * 60;
      const snapped = Math.round(totalMinutes / snapMin) * snapMin;
      const newH = Math.floor(snapped / 60);
      const newM = snapped % 60;

      // ── Horizontal: detect column under mouse ──
      const elUnderMouse = document.elementFromPoint(e.clientX, e.clientY);
      const colEl = elUnderMouse?.closest('[data-col-idx]');
      if (colEl) {
        const colIdx = parseInt(colEl.dataset.colIdx, 10);
        if (!Number.isNaN(colIdx)) {
          if (state.viewMode === 'week' && currentWeekDays?.value?.[colIdx]) {
            const newDay = currentWeekDays.value[colIdx];
            state.dragCurrentDayObj = {
              day: newDay.day,
              month: newDay.month,
              year: newDay.year,
            };
          } else if (state.viewMode === 'day' && activeAgents?.value?.[colIdx]) {
            const newAgent = activeAgents.value[colIdx];
            if (state.draggingEvent.user_id !== newAgent.id) {
              state.draggingEvent = {
                ...state.draggingEvent,
                user_id: newAgent.id,
              };
            }
          }
        }
      }

      const startDate = parseEventDate(state.draggingOriginalStartsAt);
      const endDate = parseEventDate(state.draggingOriginalEndsAt);
      const durationMs = endDate.getTime() - startDate.getTime();

      const safeH = Math.max(0, Math.min(23, newH));
      const safeM = Math.max(0, Math.min(59, newM));

      const newStartDate = new Date(
        state.dragCurrentDayObj.year,
        state.dragCurrentDayObj.month,
        state.dragCurrentDayObj.day,
        safeH,
        safeM
      );
      const newEndDate = new Date(newStartDate.getTime() + durationMs);

      state.dragCurrentStartsAt = toLocalDatetimeString(newStartDate);
      state.dragCurrentEndsAt = toLocalDatetimeString(newEndDate);

      const blockedReason = checkRangeBlocked(
        state.dragCurrentDayObj,
        state.dragCurrentStartsAt,
        state.dragCurrentEndsAt
      );
      state.dragIsBlocked = !!blockedReason;
      state.dragBlockReason = blockedReason || null;
    }

    // ── Resize (independent of drag) ──
    if (state.isResizing && state.resizingEvent) {
      const dy = e.clientY - state.initialMouseY;
      const minutesDelta = (dy / pph) * 60;
      const snapped = Math.round(minutesDelta / snapMin) * snapMin;
      const newEndMs = state.initialEndMs + snapped * 60000;
      // Minimum event size = one slot, so a resize never collapses below
      // a slot's worth of time on the grid.
      const minEndMs =
        parseEventDate(state.resizingEvent.starts_at).getTime() +
        snapMin * 60000;
      const finalMs = Math.max(newEndMs, minEndMs);
      state.resizingEventEndAt = toLocalDatetimeString(new Date(finalMs));
    }
  };

  function resetDragState() {
    const { state } = agenda;
    state.dragArmed = false;
    state.isDragging = false;
    state.dragHasMoved = false;
    state.draggingEvent = null;
    state.draggingEventId = null;
    state.dragIsBlocked = false;
    state.dragBlockReason = null;
  }

  const onGlobalMouseUp = async () => {
    const { state } = agenda;

    // ── Drag end ──
    // Only treat as drag if isDragging actually became true (threshold crossed).
    // Otherwise it was a simple click — let the click handler open the event.
    if (state.isDragging && state.draggingEvent) {
      state.skipNextClick = true;
      if (state.dragIsBlocked) {
        if (typeof onBlockedDrop === 'function') {
          try { onBlockedDrop(state.dragBlockReason); } catch { /* ignore */ }
        }
      } else {
        const payload = {
          starts_at: state.dragCurrentStartsAt,
          ends_at: state.dragCurrentEndsAt,
        };
        if (state.draggingEvent.user_id) {
          payload.user_id = state.draggingEvent.user_id;
        }
        try {
          await store.dispatch('agendaEvents/update', {
            id: state.draggingEventId,
            agenda_event: payload,
          });
        } catch {
          // ignore
        }
      }
    }
    resetDragState();

    // ── Resize end ──
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
