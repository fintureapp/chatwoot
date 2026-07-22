# Follow-up com prazo do card do Kanban SDR (N:1 com a conversa). O board não
# consulta esta tabela diretamente: o próximo follow-up aberto é espelhado em
# conversation.custom_attributes['sdr_follow_up_due_at'] via sync_mirror!,
# o que reaproveita o payload e o realtime que o board já tem.
class Finture::FollowUp < ApplicationRecord
  self.table_name = 'finture_follow_ups'

  # chave espelhada nos custom_attributes da conversa (epoch em segundos)
  MIRROR_KEY = 'sdr_follow_up_due_at'.freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :user, optional: true

  validates :title, presence: true
  validates :due_at, presence: true

  scope :open_items, -> { where(completed_at: nil) }

  def completed?
    completed_at.present?
  end

  # Recalcula o espelho após qualquer mudança (create/update/destroy).
  # Uma única gravação em custom_attributes → um único broadcast pro board.
  def self.sync_mirror!(conversation)
    next_due = where(conversation_id: conversation.id).open_items.minimum(:due_at)
    attrs = conversation.custom_attributes || {}
    return if attrs[MIRROR_KEY] == next_due&.to_i

    next_due ? attrs[MIRROR_KEY] = next_due.to_i : attrs.delete(MIRROR_KEY)
    conversation.update!(custom_attributes: attrs)
  end
end
