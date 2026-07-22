/* global axios */
import ApiClient from './ApiClient';

// Endpoints do CRM Finture aninhados em conversations (Fase 1):
// cotação estruturada (1:1 com a conversa) e follow-ups com prazo.
class FintureCrmApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getQuote(conversationId) {
    return axios.get(`${this.url}/${conversationId}/finture_quote`);
  }

  updateQuote(conversationId, payload) {
    return axios.patch(`${this.url}/${conversationId}/finture_quote`, payload);
  }

  getFollowUps(conversationId) {
    return axios.get(`${this.url}/${conversationId}/finture_follow_ups`);
  }

  createFollowUp(conversationId, payload) {
    return axios.post(
      `${this.url}/${conversationId}/finture_follow_ups`,
      payload
    );
  }

  updateFollowUp(conversationId, followUpId, payload) {
    return axios.patch(
      `${this.url}/${conversationId}/finture_follow_ups/${followUpId}`,
      payload
    );
  }

  deleteFollowUp(conversationId, followUpId) {
    return axios.delete(
      `${this.url}/${conversationId}/finture_follow_ups/${followUpId}`
    );
  }
}

export default new FintureCrmApi();
