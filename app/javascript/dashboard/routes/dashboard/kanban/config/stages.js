/**
 * Definição centralizada das etapas do Kanban SDR AI.
 *
 * `value` é o que fica persistido em `conversation.custom_attributes.sdr_stage`
 * (snake_case, estável). `label` é o nome exibido na coluna (PT-BR, dado de
 * domínio da Finture). A ordem do array é a ordem das colunas.
 *
 * Conversas sem `sdr_stage` são tratadas como `DEFAULT_STAGE` (Lead Identificado).
 */
export const KANBAN_STAGES = [
  { value: 'lead_identificado', label: 'Lead Identificado', color: 'slate' },
  { value: 'primeiro_contato', label: 'Primeiro Contato', color: 'blue' },
  { value: 'proposta_enviada', label: 'Proposta Enviada', color: 'amber' },
  { value: 'ganho', label: 'Ganho', color: 'teal' },
  { value: 'perdido', label: 'Perdido', color: 'ruby' },
];

export const DEFAULT_STAGE = 'lead_identificado';
export const WON_STAGE = 'ganho';
export const LOST_STAGE = 'perdido';

export const STAGE_VALUES = KANBAN_STAGES.map(stage => stage.value);

/**
 * Chave do custom attribute que guarda a etapa e os campos da perda.
 */
export const STAGE_ATTRIBUTE_KEY = 'sdr_stage';
export const LOST_REASON_ATTRIBUTE_KEY = 'sdr_lost_reason';
export const LOST_COMMENT_ATTRIBUTE_KEY = 'sdr_lost_comment';
export const NEXT_ACTION_ATTRIBUTE_KEY = 'sdr_next_action';

/**
 * Log estruturado de movimentações, gravado como ARRAY em
 * `custom_attributes.sdr_history`. O validador jsonb do backend só limita
 * String (<1500) e Integer; arrays passam sem cap — por isso limitamos o
 * tamanho aqui às últimas `HISTORY_MAX_ENTRIES` entradas.
 */
export const HISTORY_ATTRIBUTE_KEY = 'sdr_history';
export const HISTORY_MAX_ENTRIES = 20;

/**
 * Resolve a etapa de uma conversa, tratando ausência de valor e valores
 * desconhecidos (etapa renomeada/excluída) como a 1ª etapa válida — nunca perde
 * o card. `validSlugs` são as etapas da caixa (dinâmicas, Fase B); sem elas,
 * cai no conjunto estático de fallback.
 */
export const resolveStage = (conversation, validSlugs = STAGE_VALUES) => {
  const stage = conversation?.custom_attributes?.[STAGE_ATTRIBUTE_KEY];
  if (validSlugs.includes(stage)) return stage;
  return validSlugs[0] || DEFAULT_STAGE;
};

/**
 * Motivos de perda (dado de domínio da Finture). `value` é persistido em
 * `sdr_lost_reason`; `label` é exibido no modal.
 */
export const LOST_REASONS = [
  { value: 'sem_resposta', label: 'Sem resposta' },
  { value: 'sem_interesse', label: 'Não tinha interesse' },
  { value: 'fora_do_perfil', label: 'Fora do perfil' },
  { value: 'contato_invalido', label: 'Contato inválido' },
  { value: 'ja_contratou_outro', label: 'Já contratou com outro fornecedor' },
  { value: 'preco_condicao', label: 'Preço/condição' },
  { value: 'produto_nao_aderente', label: 'Produto não aderente' },
  { value: 'timing_ruim', label: 'Timing ruim' },
  { value: 'duplicado', label: 'Duplicado' },
  { value: 'indicacao_incorreta', label: 'Indicação incorreta' },
  { value: 'outro', label: 'Outro' },
];

/**
 * Rótulo de exibição de uma etapa a partir do seu `value` persistido.
 * Cai no rótulo da `DEFAULT_STAGE` quando o valor é desconhecido/ausente.
 */
export const stageLabel = value => {
  const stage = KANBAN_STAGES.find(item => item.value === value);
  if (stage) return stage.label;
  const fallback = KANBAN_STAGES.find(item => item.value === DEFAULT_STAGE);
  return fallback ? fallback.label : value;
};

/**
 * Rótulo de exibição de um motivo de perda a partir do seu `value` persistido.
 */
export const lostReasonLabel = value =>
  LOST_REASONS.find(reason => reason.value === value)?.label || value || '';
