# Marca o desfecho do card do Kanban SDR: ganho (won), perdido (lost) ou reabrir
# (reopen). Registra a transição em finture_stage_transitions (base do Dashboard/
# histórico) e espelha o desfecho em custom_attributes (sdr_outcome/_at + motivo/
# observação da perda). Cards com sdr_outcome saem do board ativo e passam a
# aparecer no Histórico; reabrir limpa o desfecho e devolve o card ao funil.
class Finture::OutcomeService
  OUTCOME_KEY = 'sdr_outcome'.freeze
  OUTCOME_AT_KEY = 'sdr_outcome_at'.freeze
  LOST_REASON_KEY = 'sdr_lost_reason'.freeze
  LOST_COMMENT_KEY = 'sdr_lost_comment'.freeze
  KINDS = %w[won lost reopen].freeze

  pattr_initialize [:conversation!, :kind!, :user, :reason, :comment]

  def perform
    return conversation unless KINDS.include?(kind)

    kind == 'reopen' ? reopen! : close!(kind)
    conversation
  end

  private

  def close!(outcome)
    record_transition(outcome)
    attrs = conversation.custom_attributes || {}
    attrs[OUTCOME_KEY] = outcome
    attrs[OUTCOME_AT_KEY] = Time.current.to_i
    if outcome == 'lost'
      attrs[LOST_REASON_KEY] = reason if reason.present?
      attrs[LOST_COMMENT_KEY] = comment if comment.present?
    end
    conversation.update!(custom_attributes: attrs)
  end

  def reopen!
    record_transition('reopen')
    attrs = conversation.custom_attributes || {}
    [OUTCOME_KEY, OUTCOME_AT_KEY].each { |key| attrs.delete(key) }
    conversation.update!(custom_attributes: attrs)
  end

  def current_stage
    (conversation.custom_attributes || {})['sdr_stage'] || Finture::PipelineStage::DEFAULT_SLUG
  end

  def record_transition(kind_value)
    stage = current_stage
    Finture::StageTransition.create!(
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      inbox_id: conversation.inbox_id,
      user_id: user&.id,
      from_stage: stage,
      to_stage: stage,
      to_stage_label: stage_label(stage),
      kind: kind_value,
      reason: reason,
      comment: comment,
      source: 'agent',
      occurred_at: Time.current
    )
  end

  def stage_label(slug)
    Finture::PipelineStage.where(inbox_id: conversation.inbox_id, slug: slug).pick(:name) || slug
  end
end
