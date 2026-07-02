/**
 * Configuração centralizada dos campos exibidos no card do Kanban SDR AI.
 *
 * Toda a informação do card é definida aqui — nada de campo fixo espalhado pelo
 * componente. Uma futura tela de configuração só precisa editar (ou persistir)
 * este array; o componente `KanbanCard` apenas o consome.
 *
 * Campos de cada descritor:
 *  - key      identificador único do campo
 *  - path     caminho (dot-path) para ler o valor da conversa "enriquecida"
 *  - type     'text' | 'tag' | 'date' | 'value'  (como renderizar)
 *  - primary  true = campo em destaque no topo do card
 *  - visible  false = oculto (mantido na config para fácil ativação futura)
 *  - order    ordem de exibição
 *
 * A conversa recebida pelo card é "enriquecida" com `inbox.name` (resolvido a
 * partir da store de inboxes), então `inbox.name` funciona como dot-path.
 *
 * IMPORTANTE: por decisão de produto, o card NÃO expõe temperatura, score,
 * resumo de IA nem prazo de follow-up — esses campos simplesmente não existem
 * nesta configuração.
 */
export const KANBAN_CARD_FIELDS = [
  {
    key: 'contactName',
    path: 'meta.sender.name',
    type: 'text',
    primary: true,
    visible: true,
    order: 1,
  },
  {
    key: 'value',
    path: 'custom_attributes.valor_potencial',
    type: 'value',
    primary: true,
    visible: true,
    order: 2,
  },
  {
    key: 'phone',
    path: 'meta.sender.phone_number',
    type: 'text',
    primary: false,
    visible: true,
    order: 3,
  },
  {
    key: 'email',
    path: 'meta.sender.email',
    type: 'text',
    primary: false,
    visible: false,
    order: 4,
  },
  {
    key: 'inboxName',
    path: 'inbox.name',
    type: 'text',
    primary: false,
    visible: true,
    order: 5,
  },
  {
    key: 'assignee',
    path: 'meta.assignee.name',
    type: 'text',
    primary: false,
    visible: true,
    order: 6,
  },
  {
    key: 'product',
    path: 'custom_attributes.produto_interesse',
    type: 'text',
    primary: false,
    visible: true,
    order: 7,
  },
  {
    key: 'labels',
    path: 'labels',
    type: 'tag',
    primary: false,
    visible: true,
    order: 8,
  },
  {
    key: 'createdAt',
    path: 'created_at',
    type: 'date',
    primary: false,
    visible: true,
    order: 9,
  },
  {
    key: 'priority',
    path: 'priority',
    type: 'tag',
    primary: false,
    visible: false,
    order: 10,
  },
];

/**
 * Campos visíveis, já ordenados. Consumido pelo `KanbanCard`.
 */
export const visibleCardFields = () =>
  KANBAN_CARD_FIELDS.filter(field => field.visible).sort(
    (a, b) => a.order - b.order
  );

/**
 * Lê um valor da conversa por dot-path (ex.: 'meta.sender.name').
 */
export const resolveFieldValue = (conversation, field) => {
  if (!conversation || !field?.path) return undefined;
  return field.path
    .split('.')
    .reduce(
      (acc, key) => (acc == null ? undefined : acc[key]),
      conversation
    );
};
