import ConversationApi from 'dashboard/api/inbox/conversation';
import MessageApi from 'dashboard/api/inbox/message';
import FintureCrmApi from 'dashboard/api/fintureCrm';
import {
  STAGE_ATTRIBUTE_KEY,
  NEXT_ACTION_ATTRIBUTE_KEY,
} from 'dashboard/routes/dashboard/kanban/config/stages';

const nowInSeconds = () => Math.round(Date.now() / 1000);

export const state = {
  records: [],
  selectedInboxIds: [],
  uiFlags: {
    isFetching: false,
    hasError: false,
  },
  // Etapas do funil por caixa (Fase B): fonte de verdade no backend
  // (finture_pipeline_stages), carregadas por inbox e cacheadas aqui.
  stagesByInbox: {},
  stagesUiFlags: {
    isFetching: false,
    isSaving: false,
    hasError: false,
  },
  // Histórico de leads fechados (ganho/perdido) por caixa (Fase C).
  historyByInbox: {},
  historyUiFlags: {
    isFetching: false,
    hasError: false,
  },
  // Dashboard SDR (Fase D): métricas do funil (caixa ou geral).
  dashboard: null,
  dashboardUiFlags: {
    isFetching: false,
    hasError: false,
  },
  // Notas (mensagens privadas) carregadas sob demanda, por conversa.
  notes: {},
  notesUiFlags: {
    isFetching: false,
    isCreating: false,
    hasError: false,
  },
  // Cotação estruturada e follow-ups (CRM Fase 1), carregados sob demanda no drawer.
  quotes: {},
  quoteUiFlags: {
    isFetching: false,
    isSaving: false,
    hasError: false,
  },
  followUps: {},
  followUpsUiFlags: {
    isFetching: false,
    isSaving: false,
    hasError: false,
  },
};

export const getters = {
  getRecords: $state => $state.records,
  getSelectedInboxIds: $state => $state.selectedInboxIds,
  getUIFlags: $state => $state.uiFlags,
  getRecordById: $state => id => $state.records.find(item => item.id === id),
  getStagesForInbox: $state => inboxId => $state.stagesByInbox[inboxId] || [],
  getStagesUIFlags: $state => $state.stagesUiFlags,
  getHistoryForInbox: $state => inboxId => $state.historyByInbox[inboxId] || [],
  getHistoryUIFlags: $state => $state.historyUiFlags,
  getDashboard: $state => $state.dashboard,
  getDashboardUIFlags: $state => $state.dashboardUiFlags,
  getNotes: $state => conversationId => $state.notes[conversationId] || [],
  getNotesUIFlags: $state => $state.notesUiFlags,
  getQuote: $state => conversationId => $state.quotes[conversationId] ?? null,
  getQuoteUIFlags: $state => $state.quoteUiFlags,
  getFollowUps: $state => conversationId =>
    $state.followUps[conversationId] || [],
  getFollowUpsUIFlags: $state => $state.followUpsUiFlags,
};

export const actions = {
  setSelectedInboxIds({ commit }, inboxIds) {
    commit('SET_SELECTED_INBOX_IDS', inboxIds);
  },

  // Carrega o board numa ÚNICA chamada enxuta (endpoint conversations/kanban).
  async fetchBoard({ commit, state: $state }) {
    const inboxIds = $state.selectedInboxIds;

    // Regra central: sem inbox selecionada, nada é carregado.
    if (!inboxIds.length) {
      commit('SET_RECORDS', []);
      return;
    }

    commit('SET_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await ConversationApi.kanban({ inboxIds });
      commit('SET_RECORDS', response.data?.payload ?? []);
    } catch (error) {
      commit('SET_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  // ---- Etapas do funil (Fase B) ---------------------------------------------
  async fetchStages({ commit }, { inboxId }) {
    if (!inboxId) return;
    commit('SET_STAGES_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await FintureCrmApi.getStages(inboxId);
      commit('SET_STAGES', { inboxId, stages: response.data?.payload ?? [] });
    } catch (error) {
      commit('SET_STAGES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_STAGES_UI_FLAG', { isFetching: false });
    }
  },

  async createStage({ commit }, { inboxId, stage }) {
    commit('SET_STAGES_UI_FLAG', { isSaving: true, hasError: false });
    try {
      await FintureCrmApi.createStage(inboxId, stage);
      const response = await FintureCrmApi.getStages(inboxId);
      commit('SET_STAGES', { inboxId, stages: response.data?.payload ?? [] });
    } catch (error) {
      commit('SET_STAGES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_STAGES_UI_FLAG', { isSaving: false });
    }
  },

  async updateStageConfig({ commit }, { inboxId, stageId, changes }) {
    commit('SET_STAGES_UI_FLAG', { isSaving: true, hasError: false });
    try {
      await FintureCrmApi.updateStageConfig(inboxId, stageId, changes);
      const response = await FintureCrmApi.getStages(inboxId);
      commit('SET_STAGES', { inboxId, stages: response.data?.payload ?? [] });
    } catch (error) {
      commit('SET_STAGES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_STAGES_UI_FLAG', { isSaving: false });
    }
  },

  async deleteStage({ commit }, { inboxId, stageId }) {
    commit('SET_STAGES_UI_FLAG', { isSaving: true, hasError: false });
    try {
      await FintureCrmApi.deleteStage(inboxId, stageId);
      const response = await FintureCrmApi.getStages(inboxId);
      commit('SET_STAGES', { inboxId, stages: response.data?.payload ?? [] });
    } catch (error) {
      commit('SET_STAGES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_STAGES_UI_FLAG', { isSaving: false });
    }
  },

  async reorderStages({ commit }, { inboxId, order }) {
    commit('SET_STAGES_UI_FLAG', { isSaving: true, hasError: false });
    try {
      const response = await FintureCrmApi.reorderStages(inboxId, order);
      commit('SET_STAGES', { inboxId, stages: response.data?.payload ?? [] });
    } catch (error) {
      commit('SET_STAGES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_STAGES_UI_FLAG', { isSaving: false });
    }
  },

  // Move o card de etapa NO SERVIDOR: o Finture::StageChangeService valida a
  // etapa-alvo, grava a transição (Dashboard/histórico) e espelha sdr_stage.
  async changeStage({ commit, state: $state }, { conversationId, stage }) {
    const record = $state.records.find(item => item.id === conversationId);
    const response = await FintureCrmApi.changeStage(conversationId, { stage });
    commit('UPDATE_RECORD_ATTRIBUTES', {
      conversationId,
      customAttributes: response.data?.custom_attributes ?? {
        ...(record?.custom_attributes ?? {}),
        [STAGE_ATTRIBUTE_KEY]: stage,
      },
    });
  },

  // ---- Desfecho / histórico (Fase C) ----------------------------------------
  // Marca ganho/perdido: o card sai do board ativo (passa a viver no Histórico).
  async markOutcome({ commit }, { conversationId, kind, reason, comment }) {
    await FintureCrmApi.markOutcome(conversationId, { kind, reason, comment });
    if (kind === 'won' || kind === 'lost') {
      commit('REMOVE_RECORD', conversationId);
    }
  },

  async fetchHistory({ commit }, { inboxId }) {
    if (!inboxId) return;
    commit('SET_HISTORY_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await FintureCrmApi.getHistory(inboxId);
      commit('SET_HISTORY', { inboxId, history: response.data?.payload ?? [] });
    } catch (error) {
      commit('SET_HISTORY_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_HISTORY_UI_FLAG', { isFetching: false });
    }
  },

  // Reabrir: limpa o desfecho e devolve o card ao funil ativo.
  async reopenLead({ dispatch }, { conversationId, inboxId }) {
    await FintureCrmApi.markOutcome(conversationId, { kind: 'reopen' });
    await dispatch('fetchHistory', { inboxId });
    await dispatch('fetchBoard');
  },

  // ---- Dashboard SDR (Fase D) -----------------------------------------------
  async fetchDashboard({ commit }, params) {
    commit('SET_DASHBOARD_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await FintureCrmApi.getDashboard(params);
      commit('SET_DASHBOARD', response.data ?? null);
    } catch (error) {
      commit('SET_DASHBOARD_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_DASHBOARD_UI_FLAG', { isFetching: false });
    }
  },

  // Salva a próxima ação (sdr_next_action) preservando o restante do hash.
  async updateNextAction(
    { commit, state: $state },
    { conversationId, nextAction }
  ) {
    const record = $state.records.find(item => item.id === conversationId);
    const customAttributes = {
      ...(record?.custom_attributes ?? {}),
      [NEXT_ACTION_ATTRIBUTE_KEY]: nextAction,
    };
    const response = await ConversationApi.updateCustomAttributes({
      conversationId,
      customAttributes,
    });
    commit('UPDATE_RECORD_ATTRIBUTES', {
      conversationId,
      customAttributes: response.data?.custom_attributes ?? customAttributes,
    });
  },

  // Notas = mensagens privadas. Busca a página mais recente e filtra as privadas.
  async fetchNotes({ commit }, { conversationId }) {
    commit('SET_NOTES_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await MessageApi.getPreviousMessages({ conversationId });
      const notes = (response.data?.payload ?? [])
        .filter(message => message.private)
        .map(message => ({
          id: message.id,
          content: message.content,
          createdAt: message.created_at,
          author: message.sender?.name ?? '',
        }));
      commit('SET_NOTES', { conversationId, notes });
    } catch (error) {
      commit('SET_NOTES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_NOTES_UI_FLAG', { isFetching: false });
    }
  },

  // ---- Cotação estruturada (CRM Fase 1) ------------------------------------
  async fetchQuote({ commit }, { conversationId }) {
    commit('SET_QUOTE_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await FintureCrmApi.getQuote(conversationId);
      commit('SET_QUOTE', {
        conversationId,
        quote: response.data?.quote ?? null,
      });
    } catch (error) {
      commit('SET_QUOTE_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_QUOTE_UI_FLAG', { isFetching: false });
    }
  },

  // Upsert pela aba Cotação (source=agent → sobrescreve). O espelho
  // sdr_quote_summary/valor_potencial chega ao board pelo realtime; aqui só
  // atualizamos a cotação carregada no drawer.
  async saveQuote({ commit }, { conversationId, quote }) {
    commit('SET_QUOTE_UI_FLAG', { isSaving: true, hasError: false });
    try {
      const response = await FintureCrmApi.updateQuote(conversationId, quote);
      commit('SET_QUOTE', {
        conversationId,
        quote: response.data?.quote ?? null,
      });
    } catch (error) {
      commit('SET_QUOTE_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_QUOTE_UI_FLAG', { isSaving: false });
    }
  },

  // ---- Follow-ups (CRM Fase 1) ----------------------------------------------
  async fetchFollowUps({ commit }, { conversationId }) {
    commit('SET_FOLLOW_UPS_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const response = await FintureCrmApi.getFollowUps(conversationId);
      commit('SET_FOLLOW_UPS', {
        conversationId,
        followUps: response.data?.follow_ups ?? [],
      });
    } catch (error) {
      commit('SET_FOLLOW_UPS_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_FOLLOW_UPS_UI_FLAG', { isFetching: false });
    }
  },

  async createFollowUp({ commit, dispatch }, { conversationId, followUp }) {
    commit('SET_FOLLOW_UPS_UI_FLAG', { isSaving: true, hasError: false });
    try {
      await FintureCrmApi.createFollowUp(conversationId, followUp);
      await dispatch('fetchFollowUps', { conversationId });
    } catch (error) {
      commit('SET_FOLLOW_UPS_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_FOLLOW_UPS_UI_FLAG', { isSaving: false });
    }
  },

  async updateFollowUp(
    { commit, dispatch },
    { conversationId, followUpId, changes }
  ) {
    commit('SET_FOLLOW_UPS_UI_FLAG', { isSaving: true, hasError: false });
    try {
      await FintureCrmApi.updateFollowUp(conversationId, followUpId, changes);
      await dispatch('fetchFollowUps', { conversationId });
    } catch (error) {
      commit('SET_FOLLOW_UPS_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_FOLLOW_UPS_UI_FLAG', { isSaving: false });
    }
  },

  async deleteFollowUp({ commit, dispatch }, { conversationId, followUpId }) {
    commit('SET_FOLLOW_UPS_UI_FLAG', { isSaving: true, hasError: false });
    try {
      await FintureCrmApi.deleteFollowUp(conversationId, followUpId);
      await dispatch('fetchFollowUps', { conversationId });
    } catch (error) {
      commit('SET_FOLLOW_UPS_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_FOLLOW_UPS_UI_FLAG', { isSaving: false });
    }
  },

  // ---- Realtime (CRM Fase 1) --------------------------------------------------
  // Chamada pelo actionCable em todo conversation.updated: faz merge no card
  // carregado (custom_attributes/priority/assignee) e ignora conversas fora do
  // board. O payload do cable usa o mesmo display_id do payload do kanban.
  handleConversationUpdated({ commit, state: $state }, conversation) {
    if (!conversation?.id) return;
    const record = $state.records.find(item => item.id === conversation.id);
    if (!record) return;
    commit('MERGE_RECORD_REALTIME', { conversation });
  },

  async addNote({ commit, rootGetters }, { conversationId, content }) {
    commit('SET_NOTES_UI_FLAG', { isCreating: true, hasError: false });
    try {
      const response = await MessageApi.create({
        conversationId,
        message: content,
        private: true,
      });
      const message = response.data ?? {};
      const currentUser = rootGetters.getCurrentUser;
      commit('ADD_NOTE', {
        conversationId,
        note: {
          id: message.id ?? Date.now(),
          content: message.content ?? content,
          createdAt: message.created_at ?? nowInSeconds(),
          author: message.sender?.name ?? currentUser?.name ?? '',
        },
      });
    } catch (error) {
      commit('SET_NOTES_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_NOTES_UI_FLAG', { isCreating: false });
    }
  },
};

export const mutations = {
  SET_RECORDS($state, records) {
    $state.records = records;
  },
  SET_SELECTED_INBOX_IDS($state, inboxIds) {
    $state.selectedInboxIds = inboxIds;
  },
  SET_UI_FLAG($state, uiFlag) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlag };
  },
  SET_STAGES($state, { inboxId, stages }) {
    $state.stagesByInbox = { ...$state.stagesByInbox, [inboxId]: stages };
  },
  SET_STAGES_UI_FLAG($state, uiFlag) {
    $state.stagesUiFlags = { ...$state.stagesUiFlags, ...uiFlag };
  },
  SET_HISTORY($state, { inboxId, history }) {
    $state.historyByInbox = { ...$state.historyByInbox, [inboxId]: history };
  },
  SET_HISTORY_UI_FLAG($state, uiFlag) {
    $state.historyUiFlags = { ...$state.historyUiFlags, ...uiFlag };
  },
  REMOVE_RECORD($state, conversationId) {
    $state.records = $state.records.filter(item => item.id !== conversationId);
  },
  SET_DASHBOARD($state, dashboard) {
    $state.dashboard = dashboard;
  },
  SET_DASHBOARD_UI_FLAG($state, uiFlag) {
    $state.dashboardUiFlags = { ...$state.dashboardUiFlags, ...uiFlag };
  },
  UPDATE_RECORD_ATTRIBUTES($state, { conversationId, customAttributes }) {
    const record = $state.records.find(item => item.id === conversationId);
    if (record) {
      record.custom_attributes = customAttributes;
    }
  },
  SET_NOTES($state, { conversationId, notes }) {
    $state.notes = { ...$state.notes, [conversationId]: notes };
  },
  ADD_NOTE($state, { conversationId, note }) {
    const existing = $state.notes[conversationId] || [];
    $state.notes = { ...$state.notes, [conversationId]: [...existing, note] };
  },
  SET_NOTES_UI_FLAG($state, uiFlag) {
    $state.notesUiFlags = { ...$state.notesUiFlags, ...uiFlag };
  },
  SET_QUOTE($state, { conversationId, quote }) {
    $state.quotes = { ...$state.quotes, [conversationId]: quote };
  },
  SET_QUOTE_UI_FLAG($state, uiFlag) {
    $state.quoteUiFlags = { ...$state.quoteUiFlags, ...uiFlag };
  },
  SET_FOLLOW_UPS($state, { conversationId, followUps }) {
    $state.followUps = { ...$state.followUps, [conversationId]: followUps };
  },
  SET_FOLLOW_UPS_UI_FLAG($state, uiFlag) {
    $state.followUpsUiFlags = { ...$state.followUpsUiFlags, ...uiFlag };
  },
  MERGE_RECORD_REALTIME($state, { conversation }) {
    const record = $state.records.find(item => item.id === conversation.id);
    if (!record) return;
    if (conversation.custom_attributes) {
      record.custom_attributes = conversation.custom_attributes;
    }
    if (conversation.priority !== undefined) {
      record.priority = conversation.priority;
    }
    if (conversation.meta?.assignee !== undefined) {
      record.meta = { ...record.meta, assignee: conversation.meta.assignee };
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
