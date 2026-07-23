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

  // ---- Etapas do funil (configuráveis por caixa) ----------------------------
  getStages(inboxId) {
    return axios.get(`${this.baseUrl()}/finture_pipeline_stages`, {
      params: { inbox_id: inboxId },
    });
  }

  createStage(inboxId, payload) {
    return axios.post(`${this.baseUrl()}/finture_pipeline_stages`, {
      inbox_id: inboxId,
      ...payload,
    });
  }

  updateStageConfig(inboxId, stageId, payload) {
    return axios.patch(`${this.baseUrl()}/finture_pipeline_stages/${stageId}`, {
      inbox_id: inboxId,
      ...payload,
    });
  }

  deleteStage(inboxId, stageId) {
    return axios.delete(
      `${this.baseUrl()}/finture_pipeline_stages/${stageId}`,
      {
        params: { inbox_id: inboxId },
      }
    );
  }

  reorderStages(inboxId, order) {
    return axios.post(`${this.baseUrl()}/finture_pipeline_stages/reorder`, {
      inbox_id: inboxId,
      order,
    });
  }

  // ---- Mudança de etapa do card (server-side, registra a transição) ---------
  changeStage(conversationId, payload) {
    return axios.patch(`${this.url}/${conversationId}/finture_stage`, payload);
  }

  // ---- Desfecho do card: ganho / perdido / reabrir --------------------------
  markOutcome(conversationId, payload) {
    return axios.patch(
      `${this.url}/${conversationId}/finture_outcome`,
      payload
    );
  }

  // ---- Histórico (leads fechados) de uma caixa ------------------------------
  getHistory(inboxId) {
    return axios.get(`${this.url}/kanban_history`, {
      params: { inbox_id: inboxId },
    });
  }

  // ---- Dashboard SDR (métricas do funil por caixa ou geral) -----------------
  getDashboard(params) {
    return axios.get(`${this.baseUrl()}/finture_sdr_dashboard`, { params });
  }
}

export default new FintureCrmApi();
