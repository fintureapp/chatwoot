# Modo de atendimento atual da conversa: 'ia' (bot do n8n conduz) ou 'humano'.
# Escrito só pelo Finture::AttendanceModeService. Conversa sem linha ainda tem o
# modo DERIVADO dos sinais antigos (mesma regra do guard "Avaliar Estado" do
# n8n), com revisão 0 — nada muda para as conversas existentes.
class Finture::AttendanceState < ApplicationRecord
  self.table_name = 'finture_attendance_states'

  MODES = %w[ia humano].freeze
  MODE_KEY = 'modo_atendimento'.freeze
  HUMAN_LABEL = 'atendimento_humano'.freeze

  belongs_to :account
  belongs_to :conversation

  validates :mode, inclusion: { in: MODES }
  validates :conversation_id, uniqueness: true

  # Estado persistido ou, na falta dele, um registro novo (não salvo) com o modo derivado.
  def self.for(conversation)
    conversation.finture_attendance_state || new(
      account_id: conversation.account_id, conversation: conversation,
      mode: derive_mode(conversation), revision: 0
    )
  end

  def self.derive_mode(conversation)
    legacy = (conversation.custom_attributes || {})[MODE_KEY].to_s.downcase.strip
    return 'humano' if legacy == 'humano'
    return 'ia' if legacy == 'ia'

    conversation.cached_label_list_array.include?(HUMAN_LABEL) ? 'humano' : 'ia'
  end

  # Payload exposto na conversa (lista, show, kanban, ActionCable e webhook do n8n).
  # `ai_enabled` pode vir pré-calculado para evitar consulta por conversa.
  def self.payload_for(conversation, ai_enabled: nil)
    state = self.for(conversation)
    ai_enabled = Finture::InboxConfig.ai_enabled?(conversation.inbox_id) if ai_enabled.nil?
    state.payload(ai_enabled)
  end

  def human?
    mode == 'humano'
  end

  def ia?
    mode == 'ia'
  end

  def changed_by_bot?
    changed_by_type == 'bot'
  end

  def payload(ai_enabled)
    {
      mode: mode,
      revision: revision,
      ai_enabled: ai_enabled,
      source: source,
      changed_at: changed_at&.to_i,
      changed_by_type: changed_by_type,
      changed_by_name: changed_by_name,
      resume_context: resume_context.presence
    }
  end
end
