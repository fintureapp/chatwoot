# Modo de atendimento da conversa (IA x humano) — fonte única de "quem conduz".
#
# finture_attendance_states: 1 linha por conversa com o modo atual e uma
# `revision` incrementada a cada troca. A revisão fica FORA de custom_attributes
# de propósito: fluxos do n8n regravam esse hash inteiro com cópia velha e não
# podem desfazê-la. O bot envia a revisão que leu e o servidor recusa a mensagem
# se ela mudou (alguém assumiu no meio). `resume_context` guarda o que a IA
# precisa para retomar (motivo, pendências, triagem, último responsável).
#
# finture_attendance_transitions: trilha append-only de cada troca (ator,
# origem, motivo, horário).
class CreateFintureAttendanceStates < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :finture_attendance_states do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.string :mode, null: false, default: 'ia'
      t.integer :revision, null: false, default: 0
      t.string :changed_by_type
      t.bigint :changed_by_id
      t.string :changed_by_name
      t.string :source
      t.datetime :changed_at
      t.jsonb :resume_context, null: false, default: {}
      t.timestamps
    end
    add_index :finture_attendance_states, :conversation_id, unique: true
    add_foreign_key :finture_attendance_states, :conversations, on_delete: :cascade
    add_foreign_key :finture_attendance_states, :accounts, on_delete: :cascade

    create_table :finture_attendance_transitions do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :inbox_id
      t.bigint :user_id
      t.string :actor_type, null: false
      t.string :from_mode
      t.string :to_mode, null: false
      t.string :source, null: false
      t.string :reason
      t.text :pending_notes
      t.integer :revision, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :finture_attendance_transitions, [:conversation_id, :occurred_at], name: 'index_finture_attendance_transitions_on_conv_occurred'
    add_index :finture_attendance_transitions, [:account_id, :occurred_at], name: 'index_finture_attendance_transitions_on_acct_occurred'
    add_foreign_key :finture_attendance_transitions, :conversations, on_delete: :cascade
    add_foreign_key :finture_attendance_transitions, :accounts, on_delete: :cascade
    add_foreign_key :finture_attendance_transitions, :inboxes, on_delete: :nullify
    add_foreign_key :finture_attendance_transitions, :users, on_delete: :nullify
  end
end
