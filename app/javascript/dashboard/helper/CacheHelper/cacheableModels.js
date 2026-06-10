// Single source of truth for IDB-cached workspace config.
//
// Each entry must keep `name` equal to the Rails `Model.name.underscore` value
// so the server's `cache_keys` payload (and the IDB object store name) lines up
// with what the client looks up.
//
// `dispatchPath` is the full Vuex dispatch path for the revalidate action.
// `setMutation` is the full commit path used by paintStoresFromCache to seed
// Vuex from IDB. Every SET_* mutation must REPLACE its records (not merge) so
// rows deleted server-side never survive as phantoms.
export const cacheableModels = [
  {
    name: 'inbox',
    dispatchPath: 'inboxes/revalidate',
    setMutation: 'inboxes/SET_INBOXES',
  },
  {
    name: 'label',
    dispatchPath: 'labels/revalidate',
    setMutation: 'labels/SET_LABELS',
  },
  {
    name: 'team',
    dispatchPath: 'teams/revalidate',
    setMutation: 'teams/SET_TEAMS',
  },
  {
    name: 'canned_response',
    dispatchPath: 'revalidateCannedResponses',
    setMutation: 'SET_CANNED',
  },
  {
    name: 'account_user',
    dispatchPath: 'agents/revalidate',
    setMutation: 'agents/SET_AGENTS',
  },
  {
    name: 'custom_attribute_definition',
    dispatchPath: 'attributes/revalidate',
    setMutation: 'attributes/SET_CUSTOM_ATTRIBUTE',
  },
];

export const cacheableModelNames = cacheableModels.map(model => model.name);
