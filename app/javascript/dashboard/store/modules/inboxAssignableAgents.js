import AssignableAgentsAPI from '../../api/assignableAgents';
import InboxesAPI from '../../api/inboxes';

const state = {
  records: {},
  ownerRecords: {},
  uiFlags: {
    isFetching: false,
  },
};

export const types = {
  SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG: 'SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG',
  SET_INBOX_ASSIGNABLE_AGENTS: 'SET_INBOX_ASSIGNABLE_AGENTS',
  SET_INBOX_ASSIGNABLE_OWNERS: 'SET_INBOX_ASSIGNABLE_OWNERS',
};

export const getters = {
  getAssignableAgents: $state => inboxId => {
    const allAgents = $state.records[inboxId] || [];
    const verifiedAgents = allAgents.filter(record => record.confirmed);
    return verifiedAgents;
  },
  getAssignableOwners: $state => inboxId => $state.ownerRecords[inboxId] || [],
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  async fetch({ commit }, inboxIds) {
    commit(types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload },
      } = await AssignableAgentsAPI.get(inboxIds);
      commit(types.SET_INBOX_ASSIGNABLE_AGENTS, {
        inboxId: inboxIds.join(','),
        members: payload,
      });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG, { isFetching: false });
    }
  },
  async fetchAssignableOwners({ commit }, inboxId) {
    const {
      data: { payload },
    } = await InboxesAPI.getAssignableAgents(inboxId, {
      includeAgentBots: true,
    });
    commit(types.SET_INBOX_ASSIGNABLE_OWNERS, {
      inboxId,
      owners: payload,
    });
  },
};

export const mutations = {
  [types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
  [types.SET_INBOX_ASSIGNABLE_AGENTS]: ($state, { inboxId, members }) => {
    $state.records = {
      ...$state.records,
      [inboxId]: members,
    };
  },
  [types.SET_INBOX_ASSIGNABLE_OWNERS]: ($state, { inboxId, owners }) => {
    $state.ownerRecords = {
      ...$state.ownerRecords,
      [inboxId]: owners,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
