import ConversationApi from 'dashboard/api/inbox/conversation';
import MessageApi from 'dashboard/api/inbox/message';
import {
  STAGE_ATTRIBUTE_KEY,
  LOST_REASON_ATTRIBUTE_KEY,
  LOST_COMMENT_ATTRIBUTE_KEY,
  NEXT_ACTION_ATTRIBUTE_KEY,
  HISTORY_ATTRIBUTE_KEY,
  HISTORY_MAX_ENTRIES,
  resolveStage,
} from 'dashboard/routes/dashboard/kanban/config/stages';

const nowInSeconds = () => Math.round(Date.now() / 1000);

// Autor da ação a partir do usuário logado (pode não existir em contextos sem sessão).
const authorFromUser = user =>
  user && user.id ? { id: user.id, name: user.name } : null;

export const state = {
  records: [],
  selectedInboxIds: [],
  uiFlags: {
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
};

export const getters = {
  getRecords: $state => $state.records,
  getSelectedInboxIds: $state => $state.selectedInboxIds,
  getUIFlags: $state => $state.uiFlags,
  getRecordById: $state => id => $state.records.find(item => item.id === id),
  getNotes: $state => conversationId => $state.notes[conversationId] || [],
  getNotesUIFlags: $state => $state.notesUiFlags,
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

  // Persiste a etapa (+ campos de perda) e registra a transição no histórico.
  async updateStage(
    { commit, state: $state, rootGetters },
    { conversationId, stage, lostReason, lostComment }
  ) {
    const record = $state.records.find(item => item.id === conversationId);
    const previousStage = resolveStage(record);

    // Merge obrigatório: o endpoint substitui todo o hash de custom_attributes.
    const customAttributes = {
      ...(record?.custom_attributes ?? {}),
      [STAGE_ATTRIBUTE_KEY]: stage,
    };
    if (lostReason !== undefined) {
      customAttributes[LOST_REASON_ATTRIBUTE_KEY] = lostReason;
    }
    if (lostComment !== undefined) {
      customAttributes[LOST_COMMENT_ATTRIBUTE_KEY] = lostComment;
    }

    // Log de movimentação (item 11): só quando a etapa realmente muda, evitando
    // duplicar em rebuild/rollback ou em drop na mesma coluna.
    if (previousStage !== stage) {
      const entry = {
        id: `${Date.now()}`,
        type: 'stage_change',
        from: previousStage,
        to: stage,
        at: nowInSeconds(),
        by: authorFromUser(rootGetters.getCurrentUser),
        origin: 'kanban',
      };
      if (lostReason !== undefined) entry.reason = lostReason;
      if (lostComment) entry.comment = lostComment;
      const history = Array.isArray(record?.custom_attributes?.[HISTORY_ATTRIBUTE_KEY])
        ? record.custom_attributes[HISTORY_ATTRIBUTE_KEY]
        : [];
      customAttributes[HISTORY_ATTRIBUTE_KEY] = [...history, entry].slice(
        -HISTORY_MAX_ENTRIES
      );
    }

    const response = await ConversationApi.updateCustomAttributes({
      conversationId,
      customAttributes,
    });
    commit('UPDATE_RECORD_ATTRIBUTES', {
      conversationId,
      customAttributes: response.data?.custom_attributes ?? customAttributes,
    });
  },

  // Salva a próxima ação (sdr_next_action) preservando o restante do hash.
  async updateNextAction({ commit, state: $state }, { conversationId, nextAction }) {
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
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
