# Reconciliação da Central de Demandas: reenvia ao HUB o estado ATUAL das
# conversas cujo último envio não terminou aplicado, sem depender de alguém
# mexer na conversa. Cada reenvio é um evento NOVO: `ocorrido_em` = horário do
# servidor no momento em que a reconciliação roda (data corrigida, portanto
# outro event_key no HUB) e a próxima `sequencia`. Sem autor (é o sistema).
#
# Candidatas, em lote (#perform):
#   - status `failed` (4xx ou tentativas esgotadas) e `divergent` (HUB respondeu
#     futuro/atrasado e não aplicou);
#   - `pending`/`retrying` parados há mais de STUCK_AFTER (job perdido);
#   - com include_drift: `synced` cujo conteúdo atual difere do último aplicado
#     (mudança que não chegou a gerar envio). O hash é comparado no formato do
#     v1, então a troca de versão do payload não faz nenhuma linha parecer
#     alterada.
#
# Controle de rajada: no máximo `limit` conversas por execução (padrão
# DEFAULT_LIMIT), em ordem de id; a execução seguinte pega as próximas, porque
# as já reenviadas e aplicadas saem da seleção.
#
# Idempotência: o job usa os mesmos argumentos nas retentativas (mesmo corpo,
# mesma sequência, o HUB deduplica) e, se a conversa já ficou `synced` com o
# mesmo conteúdo até o job rodar, não envia nada (:unchanged).
class Finture::DemandaReconcileService
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 1000
  STUCK_AFTER = 1.hour

  pattr_initialize [:limit, :include_drift, :dry_run]

  # Conversa a conversa (console/rake): reenvio forçado do estado atual, mesmo
  # que o conteúdo seja igual ao último aplicado. Devolve o resultado do envio.
  def self.reconcile_conversation!(conversation_id)
    Finture::DemandaSyncJob.perform_now(conversation_id, Time.current.iso8601, nil, true)
  end

  def self.candidates
    stuck = Finture::DemandaSync.where(status: %w[pending retrying]).where(updated_at: ...STUCK_AFTER.ago)
    Finture::DemandaSync.where(status: %w[failed divergent]).or(stuck)
  end

  # => { conversation_ids: [...], enqueued: bool, occurred_at: ISO-8601 }
  def perform
    ids = self.class.candidates.order(:id).limit(batch_limit).pluck(:conversation_id)
    ids += drifted_conversation_ids(batch_limit - ids.size) if include_drift && ids.size < batch_limit
    at = Time.current.iso8601
    ids.each { |id| Finture::DemandaSyncJob.perform_later(id, at) } unless dry_run
    { conversation_ids: ids, enqueued: !dry_run, occurred_at: at }
  end

  private

  def batch_limit
    value = limit.to_i
    value.positive? ? [value, MAX_LIMIT].min : DEFAULT_LIMIT
  end

  def drifted_conversation_ids(max)
    found = []
    Finture::DemandaSync.where(status: 'synced').includes(:conversation).find_each do |sync|
      break if found.size >= max
      next if sync.conversation.blank?

      service = Finture::DemandaSyncService.new(conversation: sync.conversation, occurred_at: Time.current)
      found << sync.conversation_id if service.content_changed?(sync)
    end
    found
  end
end
