import { resolveInboxChannelGroup } from './channelGroupHelper';

/**
 * Filtros rápidos da lista de conversas (barra "Filtros"): Tipo de canal,
 * Caixa, Coluna do Kanban, Status, Prioridade, Etiqueta, Time e Agente. Cada um
 * vira uma condição `equal_to` do endpoint conversations/filter (o mesmo do
 * filtro avançado), unidas por AND. "Tipo" não existe no back: vira a lista de
 * caixas do grupo (WhatsApp / E-mail / Outros) quando nenhuma caixa é escolhida.
 */

export const QUICK_FILTER_KEYS = {
  STATUS: 'status',
  PRIORITY: 'priority',
  INBOX: 'inbox_id',
  LABEL: 'labels',
  STAGE: 'sdr_stage',
  TEAM: 'team_id',
  AGENT: 'assignee_id',
};

// Tipo das caixas sem grupo (nem WhatsApp nem E-mail).
export const OTHER_CHANNEL_TYPE = 'other';

export const emptyQuickFilters = () => ({
  tipo: [],
  inbox: [],
  stage: [],
  status: [],
  priority: [],
  label: [],
  team: [],
  agent: [],
});

export const channelTypeOf = (inbox, channelGroupsMap = {}) =>
  resolveInboxChannelGroup(inbox, channelGroupsMap) || OTHER_CHANNEL_TYPE;

/** Caixas dos tipos escolhidos (todas, se nenhum tipo foi escolhido). */
export const inboxesForTipos = (tipos, inboxes, channelGroupsMap = {}) =>
  tipos?.length
    ? (inboxes || []).filter(inbox =>
        tipos.includes(channelTypeOf(inbox, channelGroupsMap))
      )
    : inboxes || [];

export const countQuickFilters = filters =>
  Object.values(filters || {}).filter(values => values?.length).length;

/**
 * Colunas do Kanban disponíveis para as caixas escolhidas (união, sem repetir
 * slug, na ordem da 1ª caixa). `stagesByInbox` = { [inboxId]: [stage] }.
 */
export const stageOptionsFor = (inboxIds, stagesByInbox) => {
  const seen = new Set();
  return (inboxIds || []).flatMap(id =>
    (stagesByInbox[id] || []).filter(stage => {
      if (seen.has(stage.slug)) return false;
      seen.add(stage.slug);
      return true;
    })
  );
};

/**
 * Conversas sem `sdr_stage` aparecem na 1ª coluna da caixa; ao filtrar por ela,
 * inclui o valor vazio (o back compara COALESCE(sdr_stage, '')).
 */
export const stageValuesFor = (slugs, inboxIds, stagesByInbox) => {
  const firstSlugs = (inboxIds || [])
    .map(id => stagesByInbox[id]?.[0]?.slug)
    .filter(Boolean);
  const includesFirst = slugs.some(slug => firstSlugs.includes(slug));
  return includesFirst ? [...slugs, ''] : [...slugs];
};

/**
 * Monta as condições do filtro. `tipoInboxIds` são as caixas do Tipo escolhido,
 * usadas quando o usuário não escolheu nenhuma caixa (tipo sem caixa = [0],
 * para a lista vir vazia em vez de trazer tudo).
 */
export const buildQuickFilterConditions = (
  filters,
  { stagesByInbox = {}, tipoInboxIds = [] } = {}
) => {
  const conditions = [];
  const push = (key, values) => {
    if (!values?.length) return;
    conditions.push({
      attribute_key: key,
      filter_operator: 'equal_to',
      values,
      query_operator: 'and',
    });
  };

  let inboxValues = filters.inbox;
  if (!inboxValues.length && filters.tipo.length) {
    inboxValues = tipoInboxIds.length ? tipoInboxIds : [0];
  }
  push(QUICK_FILTER_KEYS.INBOX, inboxValues);
  if (filters.inbox.length && filters.stage.length) {
    push(
      QUICK_FILTER_KEYS.STAGE,
      stageValuesFor(filters.stage, filters.inbox, stagesByInbox)
    );
  }
  push(QUICK_FILTER_KEYS.STATUS, filters.status);
  push(QUICK_FILTER_KEYS.PRIORITY, filters.priority);
  push(QUICK_FILTER_KEYS.LABEL, filters.label);
  push(QUICK_FILTER_KEYS.TEAM, filters.team);
  push(QUICK_FILTER_KEYS.AGENT, filters.agent);

  return conditions;
};
