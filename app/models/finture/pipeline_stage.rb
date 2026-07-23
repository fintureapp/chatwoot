# Etapa do funil do Kanban SDR, configurável POR CAIXA (inbox). A 1ª etapa
# (Lead Identificado) é `locked` e imutável (não some/renomeia slug/muda de
# posição). `slug` é o que fica em conversation.custom_attributes.sdr_stage.
# Aditivo, FK cascade → LGPD limpa; ver Finture::StageTransition.
class Finture::PipelineStage < ApplicationRecord
  self.table_name = 'finture_pipeline_stages'

  DEFAULT_SLUG = 'lead_identificado'.freeze
  COLORS = %w[slate blue teal amber ruby].freeze

  # Funil semeado numa caixa nova: Lead Identificado (travado) + as etapas
  # herdadas do Kanban v2, preservando os slugs já persistidos nos cards.
  DEFAULT_STAGES = [
    { slug: 'lead_identificado', name: 'Lead Identificado', color: 'slate', locked: true },
    { slug: 'primeiro_contato', name: 'Primeiro Contato', color: 'blue', locked: false },
    { slug: 'proposta_enviada', name: 'Proposta Enviada', color: 'amber', locked: false }
  ].freeze

  belongs_to :account
  belongs_to :inbox

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :inbox_id }
  validates :color, inclusion: { in: COLORS }

  scope :ordered, -> { order(:position, :id) }

  # Semeia o funil padrão de uma caixa (idempotente).
  def self.seed_defaults!(inbox)
    DEFAULT_STAGES.each_with_index do |attrs, index|
      stage = find_or_initialize_by(inbox_id: inbox.id, slug: attrs[:slug])
      next if stage.persisted?

      stage.assign_attributes(attrs.merge(account_id: inbox.account_id, position: index))
      stage.save!
    end
  end
end
