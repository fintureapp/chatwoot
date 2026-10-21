// Estado de trabalho do Kanban (caixa, aba, filtros, ordenação, busca do
// histórico, rolagem e card "âncora") persistido por CONTA + USUÁRIO no
// localStorage. É o que permite abrir uma conversa, voltar (botão do navegador
// ou menu) e cair no mesmo lugar. A chave inclui conta e usuário para que troca
// de conta/sessão nunca recupere filtros ou posição de outra pessoa.
import { reactive, watch } from 'vue';

const STORAGE_PREFIX = 'finture:kanban-view';
const VERSION = 1;

export const defaultViewState = () => ({
  version: VERSION,
  inboxId: null,
  activeTab: 'board',
  filters: {
    query: '',
    product: '',
    stage: '',
    assigneeId: '',
    createdFrom: '',
    createdTo: '',
  },
  sortBy: 'last_activity_desc',
  history: { query: '', outcome: '' },
  // Posição aproximada: offsets do container + id do registro clicado (âncora).
  scroll: { boardLeft: 0, historyTop: 0 },
  anchor: { kind: '', id: null, at: 0 },
});

const storageKey = (accountId, userId) =>
  `${STORAGE_PREFIX}:${accountId || 'na'}:${userId || 'na'}`;

const safeRead = key => {
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return parsed?.version === VERSION ? parsed : null;
  } catch {
    return null;
  }
};

const safeWrite = (key, value) => {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // storage cheio/bloqueado: a tela continua funcionando sem persistência
  }
};

const merge = (base, saved) => ({
  ...base,
  ...saved,
  filters: { ...base.filters, ...(saved?.filters || {}) },
  history: { ...base.history, ...(saved?.history || {}) },
  scroll: { ...base.scroll, ...(saved?.scroll || {}) },
  anchor: { ...base.anchor, ...(saved?.anchor || {}) },
});

export function useKanbanViewState({ accountId, userId }) {
  const key = storageKey(accountId, userId);
  const state = reactive(merge(defaultViewState(), safeRead(key)));

  // Persistência imediata em qualquer mudança (deep). Barato: objeto pequeno.
  watch(state, value => safeWrite(key, JSON.parse(JSON.stringify(value))), {
    deep: true,
  });

  // Registro clicado antes de sair da tela; restaurado (e destacado) ao voltar.
  const rememberAnchor = (kind, id) => {
    state.anchor = { kind, id, at: Date.now() };
  };

  const consumeAnchor = kind => {
    if (state.anchor.kind !== kind || !state.anchor.id) return null;
    const { id } = state.anchor;
    state.anchor = { kind: '', id: null, at: 0 };
    return id;
  };

  const resetFilters = () => {
    const fresh = defaultViewState();
    state.filters = fresh.filters;
    state.sortBy = fresh.sortBy;
    state.history = fresh.history;
    state.scroll = fresh.scroll;
    state.anchor = fresh.anchor;
  };

  return { state, rememberAnchor, consumeAnchor, resetFilters };
}

// Chave de provide/inject: a página instancia a composable e os descendentes
// (card, drawer, histórico, modal de perfil) só precisam de rememberAnchor.
export const KANBAN_VIEW_STATE_KEY = Symbol('kanbanViewState');
