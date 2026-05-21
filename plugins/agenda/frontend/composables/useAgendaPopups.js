import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';

export function useAgendaPopups({ agenda, agendaEvents, router, route, store, newEvent, wlScheduleEntry, openEventModal }) {
  const toggleEventInfo = ({ event, $event }) => {
    if (agenda.state.skipNextClick) {
      agenda.state.skipNextClick = false;
      return;
    }
    const rect = $event?.currentTarget?.getBoundingClientRect?.() || $event?.target?.getBoundingClientRect?.() || { top: 200, left: 200, right: 300, bottom: 250, width: 100, height: 50 };
    const isMobile = agenda.isMobile.value;
    agenda.state.eventInfoPopup = {
      eventId: event.id,
      x: isMobile ? 0 : rect.left,
      y: isMobile ? 0 : rect.top,
      right: isMobile ? 0 : rect.right,
      bottom: isMobile ? 0 : rect.bottom,
      width: isMobile ? 0 : rect.width,
    };
  };

  const closeEventInfoPopup = () => {
    agenda.state.eventInfoPopup = null;
  };

  const getInfoPopupEvent = () => {
    if (!agenda.state.eventInfoPopup) return null;
    return agendaEvents.value.find(
      e => e.id === agenda.state.eventInfoPopup.eventId
    );
  };

  const updateEventStatus = async ({ event, status }) => {
    agenda.state.statusUpdatingId = event.id;
    try {
      await store.dispatch('agendaEvents/update', {
        id: event.id,
        agenda_event: { status },
      });
    } catch {
      // ignore
    } finally {
      agenda.state.statusUpdatingId = null;
    }
  };

  const openPatientRecord = (event) => {
    const patientId = event.custom_attributes?.patient_id;
    if (patientId) {
      router.push({
        path: `/app/accounts/${route.params.accountId}/patients/${patientId}/record`,
      });
    }
  };

  const openWlScheduleForCell = ({ $event, dayObj, hour }) => {
    const entries = agenda.getWaitingListMatchForCell(
      dayObj,
      hour,
      waitingListStore.entries
    );
    const rect = $event.target.getBoundingClientRect();
    agenda.state.wlCellPopup = {
      dayObj,
      hour,
      entries,
      top: rect.bottom + 4,
      left: Math.min(rect.left, window.innerWidth - 320),
    };
    agenda.state.showWlScheduleModal = true;
  };

  const closeWlScheduleModal = () => {
    agenda.state.showWlScheduleModal = false;
    agenda.state.wlCellPopup = null;
  };

  const confirmWlSchedule = (entry) => {
    wlScheduleEntry.value = entry;
    const popup = agenda.state.wlCellPopup;
    closeWlScheduleModal();
    openEventModal({ dayObj: popup.dayObj, hourStr: popup.hour });
    newEvent.value.title = entry.contact_name;
    newEvent.value.contact_id = entry.contact_id || null;
    newEvent.value.patient_id = entry.patient_id || null;
    newEvent.value.selectedPatientName = entry.contact_name;
  };

  const showWlInfo = (entry) => {
    agenda.state.wlInfoPopup =
      agenda.state.wlInfoPopup?.entry?.id === entry.id
        ? null
        : { entry };
  };

  const closeWlInfo = () => {
    agenda.state.wlInfoPopup = null;
  };

  return {
    toggleEventInfo,
    closeEventInfoPopup,
    getInfoPopupEvent,
    updateEventStatus,
    openPatientRecord,
    openWlScheduleForCell,
    closeWlScheduleModal,
    confirmWlSchedule,
    showWlInfo,
    closeWlInfo,
  };
}
