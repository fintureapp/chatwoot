import AssignableAgentsAPI from '../../api/assignableAgents';
import InboxesAPI from '../../api/inboxes';

const state = {
  records: {},
  uiFlags: {
    isFetching: false,
  },
};

export const types = {
  SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG: 'SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG',
  SET_INBOX_ASSIGNABLE_AGENTS: 'SET_INBOX_ASSIGNABLE_AGENTS',
};

export const getters = {
  getAssignableAgents: $state => inboxId => {
    const allAgents = $state.records[inboxId] || [];
    const verifiedAgents = allAgents.filter(
      record => record.confirmed || record.assignee_type === 'AgentBot'
    );
    return verifiedAgents;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  async fetch({ commit }, request) {
    const inboxIds = Array.isArray(request) ? request : request.inboxIds;
    commit(types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload },
      } = Array.isArray(request)
        ? await AssignableAgentsAPI.get(inboxIds)
        : await InboxesAPI.getAssignableAgents(inboxIds[0], {
            includeAgentBots: true,
          });
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
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
