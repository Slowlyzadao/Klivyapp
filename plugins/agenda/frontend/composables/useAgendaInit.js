import AgendaSettingsAPI from '@plugins/agenda/frontend/api/agendaSettings';
import AgendaCustomAttributesAPI from '@plugins/agenda/frontend/api/agendaCustomAttributes';
import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';

export function useAgendaInit({ store, agendaState, checkQueryParams }) {
  const fetchInitialData = async () => {
    // Fetch stores
    store.dispatch('agents/get');
    store.dispatch('agendaEvents/get');
    store.dispatch('agendaServices/fetch');
    store.dispatch('contacts/get');
    waitingListStore.fetchAll();

    // Fetch settings
    try {
      const res = await AgendaSettingsAPI.get();
      agendaState.agendaSettingsData = res.data;
    } catch {
      // ignore
    }

    // Fetch custom attributes
    try {
      const res = await AgendaCustomAttributesAPI.getAll();
      agendaState.customAttributesConfig = res.data || [];
    } catch {
      // ignore
    }

    // Check query params if any
    if (checkQueryParams) {
      checkQueryParams();
    }
  };

  return {
    fetchInitialData,
  };
}
