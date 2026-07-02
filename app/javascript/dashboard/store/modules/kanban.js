import ConversationApi from 'dashboard/api/inbox/conversation';
import { STAGE_ATTRIBUTE_KEY } from 'dashboard/routes/dashboard/kanban/config/stages';

export const PER_PAGE = 25;
// Teto de segurança para o carregamento do board (ver limitações no plano).
export const MAX_PAGES = 8;

export const state = {
  records: [],
  selectedInboxIds: [],
  uiFlags: {
    isFetching: false,
    hasError: false,
  },
};

export const getters = {
  getRecords: $state => $state.records,
  getSelectedInboxIds: $state => $state.selectedInboxIds,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  setSelectedInboxIds({ commit }, inboxIds) {
    commit('SET_SELECTED_INBOX_IDS', inboxIds);
  },

  async fetchBoard({ commit, state: $state }) {
    const inboxIds = $state.selectedInboxIds;

    // Regra central: sem inbox selecionada, nada é carregado.
    if (!inboxIds.length) {
      commit('SET_RECORDS', []);
      return;
    }

    commit('SET_UI_FLAG', { isFetching: true, hasError: false });
    try {
      const records = [];
      for (let page = 1; page <= MAX_PAGES; page += 1) {
        // eslint-disable-next-line no-await-in-loop
        const response = await ConversationApi.get({
          inboxId: inboxIds,
          status: 'all',
          assigneeType: 'all',
          page,
          sortBy: 'last_activity_at_desc',
        });
        const payload = response.data?.data?.payload ?? [];
        records.push(...payload);
        if (payload.length < PER_PAGE) break;
      }
      commit('SET_RECORDS', records);
    } catch (error) {
      commit('SET_UI_FLAG', { hasError: true });
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async updateStage(
    { commit, state: $state },
    { conversationId, stage, lostReason, lostComment }
  ) {
    const record = $state.records.find(item => item.id === conversationId);
    // Merge obrigatório: o endpoint substitui todo o hash de custom_attributes.
    const customAttributes = {
      ...(record?.custom_attributes ?? {}),
      [STAGE_ATTRIBUTE_KEY]: stage,
    };
    if (lostReason !== undefined) {
      customAttributes.sdr_lost_reason = lostReason;
    }
    if (lostComment !== undefined) {
      customAttributes.sdr_lost_comment = lostComment;
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
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
