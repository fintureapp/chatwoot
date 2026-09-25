# Etapa do funil do Kanban SDR, configurável POR CAIXA (inbox). A 1ª etapa
# (Lead Identificado) é `locked` e imutável (não some/renomeia slug/muda de
# posição). `slug` é o que fica em conversation.custom_attributes.sdr_stage.
# Aditivo, FK cascade → LGPD limpa; ver Finture::StageTransition.
class Finture::PipelineStage < ApplicationRecord
  self.table_name = 'finture_pipeline_stages'

  DEFAULT_SLUG = 'lead_identificado'.freeze
  COLORS = %w[slate blue teal amber ruby].freeze

  # Funil comercial semeado numa caixa nova: Lead Identificado (travado) + as
  # etapas herdadas do Kanban v2, preservando os slugs já persistidos nos cards.
  COMMERCIAL_DEFAULT_STAGES = [
    { slug: 'lead_identificado', name: 'Lead Identificado', color: 'slate', locked: true },
    { slug: 'primeiro_contato', name: 'Primeiro Contato', color: 'blue', locked: false },
    { slug: 'proposta_enviada', name: 'Proposta Enviada', color: 'amber', locked: false }
  ].freeze

  # Funil operacional (atendimento): não tem ganho/perdido — a demanda sai do
  # board ao ser resolvida. A 1ª etapa (Chamada Iniciada) é travada.
  OPERATIONAL_DEFAULT_STAGES = [
    { slug: 'chamada_iniciada', name: 'Chamada Iniciada', color: 'slate', locked: true },
    { slug: 'em_triagem', name: 'Em Triagem', color: 'blue', locked: false },
    { slug: 'em_atendimento', name: 'Em Atendimento', color: 'teal', locked: false }
  ].freeze

  # Mantido para compatibilidade (rake de seed/backfill legado usa DEFAULT_STAGES).
  DEFAULT_STAGES = COMMERCIAL_DEFAULT_STAGES

  belongs_to :account
  belongs_to :inbox

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :inbox_id }
  validates :color, inclusion: { in: COLORS }

  scope :ordered, -> { order(:position, :id) }

  # Conjunto de etapas padrão conforme a classificação da caixa.
  def self.default_stages_for(kanban_type)
    kanban_type.to_s == 'operacional' ? OPERATIONAL_DEFAULT_STAGES : COMMERCIAL_DEFAULT_STAGES
  end

  # Semeia o funil padrão de uma caixa (idempotente). O tipo define o conjunto de
  # etapas semeadas; sem tipo, usa o comercial (comportamento anterior).
  def self.seed_defaults!(inbox, kanban_type = nil)
    default_stages_for(kanban_type).each_with_index do |attrs, index|
      stage = find_or_initialize_by(inbox_id: inbox.id, slug: attrs[:slug])
      next if stage.persisted?

      stage.assign_attributes(attrs.merge(account_id: inbox.account_id, position: index))
      stage.save!
    end
  end
end
