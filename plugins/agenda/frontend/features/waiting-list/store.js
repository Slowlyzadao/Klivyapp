/**
 * waiting-list/store.js
 *
 * Store reativo para a Lista de Espera.
 *
 * Os dados são persistidos no banco de dados via API Rails,
 * NÃO no localStorage.
 */

import { reactive } from 'vue';
import waitingListApi from './api';

export const waitingListStore = reactive({
  entries: [],
  loading: false,
  loaded: false,

  /** Carrega todas as entradas do banco. Deve ser chamado ao montar a Agenda. */
  async fetchAll() {
    if (this.loading) return;
    this.loading = true;
    try {
      const { data } = await waitingListApi.get();
      this.entries = data;
      this.loaded = true;
    } catch (e) {
      // silencia erros (ex: 401 antes do login)
    } finally {
      this.loading = false;
    }
  },

  /** Adiciona ou atualiza uma entrada no banco (upsert por contact_id). */
  async save(entry) {
    const { data } = await waitingListApi.create({
      waiting_list_entry: {
        contact_id: entry.contactId,
        period: entry.period,
        specific_time: entry.specificTime || null,
        preferred_days: entry.preferredDays || [],
        notes: entry.notes || '',
      },
    });
    // Atualiza local: remove entrada existente do mesmo contato e adiciona nova
    const idx = this.entries.findIndex(e => e.contact_id === data.contact_id);
    if (idx !== -1) {
      this.entries[idx] = data;
    } else {
      this.entries.push(data);
    }
    return data;
  },

  /** Remove uma entrada pelo ID do banco. */
  async remove(id) {
    await waitingListApi.delete(id);
    const idx = this.entries.findIndex(e => e.id === id);
    if (idx !== -1) this.entries.splice(idx, 1);
  },
});

/**
 * Verifica se um horário (HH:MM) está dentro do período.
 * morning:   06:00–12:00
 * afternoon: 12:00–18:00
 * evening:   18:00–24:00
 */
export function isTimeInPeriod(time, period) {
  const h =
    typeof time === 'string'
      ? parseInt(time.split(':')[0], 10)
      : time.getHours();
  if (period === 'morning') return h >= 6 && h < 12;
  if (period === 'afternoon') return h >= 12 && h < 18;
  if (period === 'evening') return h >= 18 && h < 24;
  return false;
}
