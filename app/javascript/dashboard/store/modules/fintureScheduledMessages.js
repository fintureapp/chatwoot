// Mensagens agendadas por conversa (Finture). `meta` traz a janela do canal
// (quando fecha) para o diálogo de agendamento avisar antes de agendar.
import FintureCrmApi from 'dashboard/api/fintureCrm';

const state = {
  byConversation: {},
  metaByConversation: {},
  uiFlags: { isFetching: false, isSaving: false },
};

export const getters = {
  getForConversation: $state => conversationId =>
    $state.byConversation[conversationId] || [],
  getPendingForConversation: $state => conversationId =>
    ($state.byConversation[conversationId] || []).filter(
      item => item.status === 'pending'
    ),
  getMeta: $state => conversationId =>
    $state.metaByConversation[conversationId] || {},
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  async fetch({ commit }, { conversationId }) {
    commit('setUIFlag', { isFetching: true });
    try {
      const { data } = await FintureCrmApi.getScheduledMessages(conversationId);
      commit('setItems', {
        conversationId,
        items: data.payload,
        meta: data.meta,
      });
    } finally {
      commit('setUIFlag', { isFetching: false });
    }
  },
  async create({ commit }, { conversationId, payload }) {
    commit('setUIFlag', { isSaving: true });
    try {
      const { data } = await FintureCrmApi.createScheduledMessage(
        conversationId,
        payload
      );
      const { meta, ...item } = data;
      commit('upsertItem', { conversationId, item, meta });
      return item;
    } finally {
      commit('setUIFlag', { isSaving: false });
    }
  },
  async update({ commit }, { conversationId, id, payload }) {
    commit('setUIFlag', { isSaving: true });
    try {
      const { data } = await FintureCrmApi.updateScheduledMessage(
        conversationId,
        id,
        payload
      );
      commit('upsertItem', { conversationId, item: data });
      return data;
    } finally {
      commit('setUIFlag', { isSaving: false });
    }
  },
  async cancel({ commit }, { conversationId, id }) {
    commit('setUIFlag', { isSaving: true });
    try {
      const { data } = await FintureCrmApi.cancelScheduledMessage(
        conversationId,
        id
      );
      commit('upsertItem', { conversationId, item: data });
      return data;
    } finally {
      commit('setUIFlag', { isSaving: false });
    }
  },
};

export const mutations = {
  setUIFlag($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  setItems($state, { conversationId, items, meta }) {
    $state.byConversation = {
      ...$state.byConversation,
      [conversationId]: items,
    };
    if (meta) {
      $state.metaByConversation = {
        ...$state.metaByConversation,
        [conversationId]: meta,
      };
    }
  },
  upsertItem($state, { conversationId, item, meta }) {
    const current = $state.byConversation[conversationId] || [];
    const index = current.findIndex(existing => existing.id === item.id);
    const next = [...current];
    if (index === -1) next.unshift(item);
    else next[index] = item;
    $state.byConversation = {
      ...$state.byConversation,
      [conversationId]: next,
    };
    if (meta) {
      $state.metaByConversation = {
        ...$state.metaByConversation,
        [conversationId]: meta,
      };
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
