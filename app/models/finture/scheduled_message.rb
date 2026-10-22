# Mensagem agendada numa conversa. Ver migration para o ciclo de vida.
#
# Política explícita (o que acontece entre agendar e enviar):
#   - cliente respondeu antes e `cancel_on_reply` ligado → cancelado (client_replied);
#   - transferência de responsável, resolução da conversa ou troca IA/humano
#     NÃO cancelam: a mensagem sai no horário, assinada pelo autor original;
#   - regras do canal são checadas no envio (janela do WhatsApp etc.): fora da
#     janela a mensagem NÃO é enviada e vira `failed`, com aviso ao autor;
#   - agendamento de TEMPLATE (template_params preenchido) não depende da
#     janela: template aprovado pode ser enviado com a janela de 24h fechada.
class Finture::ScheduledMessage < ApplicationRecord
  self.table_name = 'finture_scheduled_messages'

  TIMEZONE = 'America/Sao_Paulo'.freeze
  STATUSES = %w[pending processing sent failed cancelled].freeze
  STALE_PROCESSING_AFTER = 15.minutes

  belongs_to :account
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :user, optional: true
  belongs_to :message, optional: true

  validates :content, presence: true
  validates :scheduled_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :scheduled_in_future, on: :create
  validate :template_params_shape

  scope :pending, -> { where(status: 'pending') }
  scope :due, -> { pending.where(scheduled_at: ..Time.current) }
  scope :stale_processing, -> { where(status: 'processing').where(processing_at: ...STALE_PROCESSING_AFTER.ago) }

  def pending?
    status == 'pending'
  end

  def template?
    template_params.present?
  end

  # Reivindica o registro para envio. Só um worker vence (UPDATE condicional).
  def claim!
    self.class.where(id: id, status: 'pending').update_all(status: 'processing', processing_at: Time.current) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  def self.timezone
    ActiveSupport::TimeZone[TIMEZONE]
  end

  # "2026-10-21T15:30" (hora de parede em America/Sao_Paulo) → Time UTC.
  def self.parse_local(value)
    return nil if value.blank?

    timezone.parse(value.to_s)
  end

  private

  def scheduled_in_future
    return if scheduled_at.blank?

    errors.add(:scheduled_at, 'deve ser no futuro') if scheduled_at <= Time.current
  end

  def template_params_shape
    return if template_params.nil?

    return errors.add(:template_params, 'precisa do nome do template') if !template_params.is_a?(Hash) || template_params['name'].blank?

    body = template_params.dig('processed_params', 'body')
    errors.add(:template_params, 'tem variáveis sem preencher') if body.is_a?(Hash) && body.values.any?(&:blank?)
  end
end
