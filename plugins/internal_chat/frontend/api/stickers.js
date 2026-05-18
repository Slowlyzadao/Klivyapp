/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatStickersAPI extends ApiClient {
  constructor() {
    super('internal_chat/stickers', { accountScoped: true });
  }

  // Filtros: 'all' | 'mine' | 'favorites' | 'default'
  list(filter = 'all') {
    return axios.get(this.url, { params: { filter } });
  }

  // blob: WebP 512x512 já processado pelo client
  upload({ blob, name, width, height }) {
    const form = new FormData();
    form.append('image', blob, 'sticker.webp');
    if (name) form.append('name', name);
    if (width) form.append('width', String(width));
    if (height) form.append('height', String(height));
    return axios.post(this.url, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  favorite(stickerId) {
    return axios.post(`${this.url}/${stickerId}/favorite`);
  }

  unfavorite(stickerId) {
    return axios.delete(`${this.url}/${stickerId}/favorite`);
  }
}

export default new InternalChatStickersAPI();
