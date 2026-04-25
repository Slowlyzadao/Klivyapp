/* global axios */
import ApiClient from 'dashboard/api/ApiClient';
import AgendaSettingsAPI from './agendaSettings';

// Reads schedule config from the API (falls back to empty if unavailable)
let cachedScheduleParams = null;

async function readScheduleParams() {
  if (cachedScheduleParams) return cachedScheduleParams;

  try {
    const { data } = await AgendaSettingsAPI.get();
    const weekDays = data.week_days || [];

    // Determine open days (0=Sun, 1=Mon, ... 6=Sat)
    const dayIdToWday = {
      sun: 0,
      mon: 1,
      tue: 2,
      wed: 3,
      thu: 4,
      fri: 5,
      sat: 6,
    };
    const openDays = weekDays
      .filter(d => d.enabled)
      .map(d => dayIdToWday[d.id])
      .filter(n => n !== undefined);

    // Parse open/close hours from first enabled weekday (Mon-Fri as reference)
    const refDay = weekDays.find(
      d => d.enabled && d.id !== 'sat' && d.id !== 'sun'
    );
    const parseHour = t => (t ? parseInt(t.split(':')[0], 10) : null);

    const openHour = refDay ? parseHour(refDay.start) : 9;
    const closeHour = refDay ? parseHour(refDay.end) : 18;

    // Lunch duration
    let lunchMins = 0;
    if (
      data.block_lunch_break &&
      refDay &&
      refDay.lunchStart &&
      refDay.lunchEnd
    ) {
      const ls = parseHour(refDay.lunchStart);
      const le = parseHour(refDay.lunchEnd);
      lunchMins = Math.max((le - ls) * 60, 0);
    }

    const result = {};
    if (openHour !== null) result.open_hour = openHour;
    if (closeHour !== null) result.close_hour = closeHour;
    if (lunchMins > 0) result.lunch_duration_minutes = lunchMins;
    if (openDays.length > 0) result.open_days = openDays.join(',');

    cachedScheduleParams = result;
    // Invalidate cache after 5 minutes
    setTimeout(
      () => {
        cachedScheduleParams = null;
      },
      5 * 60 * 1000
    );

    return result;
  } catch {
    return {};
  }
}

class AgendaReportsAPI extends ApiClient {
  constructor() {
    super('agenda_reports', { accountScoped: true });
  }

  async getSummary({ since, until: untilDate, userId } = {}) {
    const scheduleParams = await readScheduleParams();
    const params = { ...scheduleParams };
    if (since) params.since = since;
    if (untilDate) params.until = untilDate;
    if (userId) params.user_id = userId;

    return axios.get(`${this.url}/summary`, { params });
  }

  async getForecast({ days = 7, userId } = {}) {
    const scheduleParams = await readScheduleParams();
    const params = { days, ...scheduleParams };
    if (userId) params.user_id = userId;
    return axios.get(`${this.url}/forecast`, { params });
  }
}

export default new AgendaReportsAPI();
