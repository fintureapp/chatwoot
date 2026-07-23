# Muda a etapa do card do Kanban SDR NO SERVIDOR: valida a etapa-alvo contra o
# funil da caixa, registra a transição em finture_stage_transitions (base do
# Dashboard/histórico) e espelha `sdr_stage` nos custom_attributes — uma única
# gravação → um único broadcast pro board. Regras de convivência IA/humano
# iguais às da cotação: source 'agent' sobrescreve; 'n8n' só preenche etapa
# vazia. Substitui a escrita client-side (que trocava o hash inteiro de
# custom_attributes e montava sdr_history no navegador).
class Finture::StageChangeService
  STAGE_KEY = 'sdr_stage'.freeze

  pattr_initialize [:conversation!, :to_stage!, :source!, :user, :reason, :comment]

  def perform
    return conversation if invalid_target? || blocked_for_ai?

    from = current_stage
    return conversation if from == to_stage

    record_transition(from)
    mirror_stage!
    conversation
  end

  private

  def invalid_target?
    stage_slugs.exclude?(to_stage)
  end

  # IA (n8n) nunca sobrescreve etapa já definida por humano; só preenche vazio.
  def blocked_for_ai?
    source == 'n8n' && raw_stage.present?
  end

  def stages
    @stages ||= Finture::PipelineStage.where(inbox_id: conversation.inbox_id).ordered.to_a
  end

  def stage_slugs
    stages.map(&:slug)
  end

  def raw_stage
    (conversation.custom_attributes || {})[STAGE_KEY]
  end

  def current_stage
    stage_slugs.include?(raw_stage) ? raw_stage : Finture::PipelineStage::DEFAULT_SLUG
  end

  def stage_label(slug)
    stages.find { |stage| stage.slug == slug }&.name || slug
  end

  def record_transition(from)
    Finture::StageTransition.create!(
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      inbox_id: conversation.inbox_id,
      user_id: user&.id,
      from_stage: from,
      to_stage: to_stage,
      to_stage_label: stage_label(to_stage),
      kind: 'stage_change',
      reason: reason,
      comment: comment,
      source: source,
      occurred_at: Time.current
    )
  end

  def mirror_stage!
    attrs = conversation.custom_attributes || {}
    attrs[STAGE_KEY] = to_stage
    conversation.update!(custom_attributes: attrs)
  end
end
