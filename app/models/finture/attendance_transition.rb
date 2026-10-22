# Troca de modo de atendimento (append-only): quem, de onde, quando e por quê.
# Gravada pelo Finture::AttendanceModeService na mesma transação da troca.
class Finture::AttendanceTransition < ApplicationRecord
  self.table_name = 'finture_attendance_transitions'

  ACTOR_TYPES = %w[user bot system].freeze
  SOURCES = %w[
    dashboard_take_over dashboard_return n8n_handoff legacy_api label assignment agent_created reopen_by_contact
  ].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :inbox, optional: true
  belongs_to :user, optional: true

  validates :to_mode, inclusion: { in: Finture::AttendanceState::MODES }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }
  validates :source, inclusion: { in: SOURCES }

  scope :chronological, -> { order(:occurred_at, :id) }
end
