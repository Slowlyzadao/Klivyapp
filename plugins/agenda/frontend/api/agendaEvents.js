import ApiClient from 'dashboard/api/ApiClient';

class AgendaEventsAPI extends ApiClient {
  constructor() {
    super('agenda_events', { accountScoped: true });
  }

  filter({ userId, contactId, status, startsAt, endsAt }) {
    const params = {};
    if (userId) params.user_id = userId;
    if (contactId) params.contact_id = contactId;
    if (status) params.status = status;
    if (startsAt) params.starts_at = startsAt;
    if (endsAt) params.ends_at = endsAt;

    return this.get({ params });
  }
}

export default new AgendaEventsAPI();
