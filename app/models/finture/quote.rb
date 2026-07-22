# Cotação estruturada multi-produto do lead — 1:1 com a conversa (o card do
# Kanban SDR é a própria conversation). A seção específica do produto vive em
# `data`; para saúde PME as vidas seguem as 10 faixas etárias fixas da ANS
# (chaves do jsonb), formato que as operadoras usam para precificar.
class Finture::Quote < ApplicationRecord
  self.table_name = 'finture_quotes'

  PRODUCT_TYPES = %w[saude_pme consorcio seguros credito].freeze
  SOURCES = %w[agent n8n].freeze
  # Faixas etárias do padrão ANS (RN 63/2003) — mesmas chaves do widget de
  # vidas da aba Cotação e do payload do n8n.
  ANS_AGE_BANDS = %w[0-18 19-23 24-28 29-33 34-38 39-43 44-48 49-53 54-58 59+].freeze
  ACCOMMODATIONS = %w[enfermaria apartamento].freeze

  belongs_to :account
  belongs_to :conversation

  validates :conversation_id, uniqueness: true
  validates :product_type, inclusion: { in: PRODUCT_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :total_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :data_structure

  def lives
    (data || {})['lives'] || {}
  end

  def lives_total
    lives.values.sum(&:to_i)
  end

  private

  def data_structure
    return errors.add(:data, 'deve ser um objeto') unless data.is_a?(Hash)
    return unless product_type == 'saude_pme'

    errors.add(:data, 'faixas etárias fora do padrão ANS') if lives.is_a?(Hash) && (lives.keys - ANS_AGE_BANDS).any?
    accommodation = data['accommodation']
    errors.add(:data, 'acomodação inválida') if accommodation.present? && ACCOMMODATIONS.exclude?(accommodation)
  end
end
