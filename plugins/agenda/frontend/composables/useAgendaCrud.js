import { padZ, toLocalDatetimeString, createDefaultNewEvent, parseEventDate } from '../utils/agenda-date.js';
import { useAlert } from 'dashboard/composables';
import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';

export function useAgendaCrud({ agenda, store, router, route, newEvent, wlScheduleEntry, _returnPatientId }) {
  const currentUserID = () => store.getters['getCurrentUser']?.id;

  const openEventModal = ({ dayObj, hourStr, agent } = {}) => {
    const now = new Date();
    const date = dayObj
      ? `${dayObj.year}-${padZ(dayObj.month + 1)}-${padZ(dayObj.day)}`
      : `${now.getFullYear()}-${padZ(now.getMonth() + 1)}-${padZ(now.getDate())}`;
    const timeStart = hourStr || '09:00';
    const [h, m] = timeStart.split(':').map(Number);
    const endMinutes = h * 60 + m + 60;
    const timeEnd = `${padZ(Math.floor(endMinutes / 60) % 24)}:${padZ(endMinutes % 60)}`;

    newEvent.value = createDefaultNewEvent({
      date,
      time_start: timeStart,
      time_end: timeEnd,
      user_id: agent?.id || currentUserID(),
    });
    agenda.state.isEditing = false;
    agenda.state.editingEventId = null;
    agenda.state.showNewEventModal = true;
  };

  const closeEventModal = () => {
    agenda.state.showNewEventModal = false;
    agenda.state.isEditing = false;
    agenda.state.editingEventId = null;
  };

  const openEditEvent = (event) => {
    const startDate = parseEventDate(event.starts_at);
    const endDate = parseEventDate(event.ends_at);
    newEvent.value = {
      title: event.title,
      event_type: event.event_type || 'consultation',
      priority: event.custom_attributes?.priority || 'medium',
      treatment: event.custom_attributes?.treatment || '',
      date: `${startDate.getFullYear()}-${padZ(startDate.getMonth() + 1)}-${padZ(startDate.getDate())}`,
      time_start: `${padZ(startDate.getHours())}:${padZ(startDate.getMinutes())}`,
      time_end: `${padZ(endDate.getHours())}:${padZ(endDate.getMinutes())}`,
      user_id: event.user_id,
      contact_id: event.contact_id || null,
      patient_id: event.custom_attributes?.patient_id || null,
      description: event.description || '',
      selectedPatientName: event.custom_attributes?.patient_name || event.title,
      selectedPatientPhone: event.custom_attributes?.patient_phone || '',
      selectedPatientAvatarUrl: event.custom_attributes?.patient_avatar_url || null,
      custom_values: {},
    };
    // Populate custom attribute values
    if (agenda.state.customAttributesConfig.length && event.custom_attributes) {
      agenda.state.customAttributesConfig.forEach(attr => {
        const key = `attr_${attr.id}`;
        if (event.custom_attributes[key] !== undefined) {
          newEvent.value.custom_values[key] = event.custom_attributes[key];
        }
      });
    }
    agenda.state.isEditing = true;
    agenda.state.editingEventId = event.id;
    agenda.state.showNewEventModal = true;
    agenda.state.eventInfoPopup = null;
  };

  const saveEvent = async () => {
    if (!newEvent.value.title) return;

    // Validate required custom attributes
    for (const attr of agenda.state.customAttributesConfig) {
      if (attr.required) {
        const val = newEvent.value.custom_values[`attr_${attr.id}`];
        if (!val || (attr.type === 'cpf' && !String(val).replace(/\D/g, ''))) {
          useAlert(`O campo '${attr.name}' é obrigatório.`);
          return;
        }
      }
    }

    // Validate hours
    const startH = Number(newEvent.value.time_start.split(':')[0]);
    const endH = Number(newEvent.value.time_end.split(':')[0]);
    const endM = Number(newEvent.value.time_end.split(':')[1] || 0);
    const [y, mo, d] = newEvent.value.date.split('-');
    const dayObj = { year: Number(y), month: Number(mo) - 1, day: Number(d) };

    for (let h = startH; h <= endH; h += 1) {
      if (h === endH && endM === 0 && h !== startH) break;
      if (agenda.isHourBlocked(dayObj, `${padZ(h)}:00`)) {
        agenda.getBlockedMessage(dayObj, `${padZ(h)}:00`, useAlert);
        return;
      }
    }

    agenda.state.isSaving = true;
    try {
      const startsAtDate = new Date(`${newEvent.value.date}T${newEvent.value.time_start}`);
      let endsAtDate = new Date(`${newEvent.value.date}T${newEvent.value.time_end}`);
      if (endsAtDate <= startsAtDate) {
        endsAtDate = new Date(startsAtDate.getTime() + 60 * 60 * 1000);
      }

      const payload = {
        title: newEvent.value.title,
        description: newEvent.value.description,
        event_type: newEvent.value.event_type,
        starts_at: toLocalDatetimeString(startsAtDate),
        ends_at: toLocalDatetimeString(endsAtDate),
        user_id: newEvent.value.user_id,
        contact_id: newEvent.value.contact_id,
        custom_attributes: {
          priority: newEvent.value.priority,
          treatment: newEvent.value.treatment,
          patient_id: newEvent.value.patient_id || null,
          patient_name: newEvent.value.selectedPatientName || null,
          patient_phone: newEvent.value.selectedPatientPhone || null,
          patient_avatar_url: newEvent.value.selectedPatientAvatarUrl || null,
          ...(newEvent.value.custom_values || {}),
        },
      };

      if (agenda.state.isEditing) {
        await store.dispatch('agendaEvents/update', {
          id: agenda.state.editingEventId,
          agenda_event: payload,
        });
      } else {
        await store.dispatch('agendaEvents/create', {
          agenda_event: { ...payload, status: 'scheduled' },
        });
        if (wlScheduleEntry.value?.id) {
          await waitingListStore.remove(wlScheduleEntry.value.id);
          wlScheduleEntry.value = null;
        }
      }

      closeEventModal();

      if (_returnPatientId.value) {
        router.push({
          path: `/app/accounts/${route.params.accountId}/patients/${_returnPatientId.value}/record`,
          query: { tab: 'schedule' },
        });
        _returnPatientId.value = null;
      }
    } catch {
      // ignore
    } finally {
      agenda.state.isSaving = false;
    }
  };

  const deleteEvent = () => {
    agenda.state.showConfirmDelete = true;
  };

  const cancelDelete = () => {
    agenda.state.showConfirmDelete = false;
  };

  const confirmDelete = async ({ reason, note }) => {
    agenda.state.isDeleting = true;
    try {
      await store.dispatch('agendaEvents/delete', agenda.state.editingEventId);
      agenda.state.showConfirmDelete = false;
      closeEventModal();
    } catch {
      // ignore
    } finally {
      agenda.state.isDeleting = false;
    }
  };

  const quickDeleteEvent = (event) => {
    agenda.state.editingEventId = event.id;
    agenda.state.showConfirmDelete = true;
  };

  const checkQueryParams = () => {
    const q = route.query;
    if (q.new_event === 'true') {
      openEventModal();
      if (q.patient_id) {
        _returnPatientId.value = q.patient_id;
        newEvent.value.patient_id = Number(q.patient_id);
        newEvent.value.selectedPatientName = q.patient_name || '';
        newEvent.value.title = q.patient_name || '';
        if (q.contact_id) newEvent.value.contact_id = Number(q.contact_id);
      }
    }
  };

  return {
    openEventModal,
    closeEventModal,
    openEditEvent,
    saveEvent,
    deleteEvent,
    cancelDelete,
    confirmDelete,
    quickDeleteEvent,
    checkQueryParams,
  };
}
