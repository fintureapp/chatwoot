# Transição de etapa / desfecho do Kanban SDR (append-only). Fonte de verdade do
# Dashboard SDR (tempo médio por etapa, conversão) e do histórico do card.
# Gravada server-side pelo Finture::StageChangeService / Finture::OutcomeService.
class Finture::StageTransition < ApplicationRecord
  self.table_name = 'finture_stage_transitions'

  KINDS = %w[stage_change won lost reopen].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :inbox, optional: true
  belongs_to :user, optional: true

  validates :to_stage, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :chronological, -> { order(:occurred_at, :id) }
end
