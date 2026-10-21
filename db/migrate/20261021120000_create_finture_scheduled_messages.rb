# Mensagens agendadas dentro da conversa (Finture). O registro é a fonte da
# verdade do agendamento: o envio de verdade vira uma Message normal (message_id)
# criada pelo job no horário previsto. `status`: pending | processing | sent |
# failed | cancelled. A transição pending→processing é atômica (update_all com
# WHERE status='pending'), o que garante um único envio mesmo com retry/reinício.
class CreateFintureScheduledMessages < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :finture_scheduled_messages do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :user_id
      t.text :content, null: false
      t.datetime :scheduled_at, null: false
      t.string :status, null: false, default: 'pending'
      t.boolean :cancel_on_reply, null: false, default: true
      t.datetime :processing_at
      t.datetime :sent_at
      t.bigint :message_id
      t.string :cancel_reason
      t.text :error_message
      t.timestamps
    end
    add_index :finture_scheduled_messages, [:conversation_id, :scheduled_at], name: 'index_finture_scheduled_messages_on_conv_scheduled'
    add_index :finture_scheduled_messages, [:status, :scheduled_at], name: 'index_finture_scheduled_messages_on_status_scheduled'
    add_foreign_key :finture_scheduled_messages, :accounts, on_delete: :cascade
    add_foreign_key :finture_scheduled_messages, :conversations, on_delete: :cascade
    add_foreign_key :finture_scheduled_messages, :inboxes, on_delete: :cascade
    add_foreign_key :finture_scheduled_messages, :users, on_delete: :nullify
    add_foreign_key :finture_scheduled_messages, :messages, on_delete: :nullify
  end
end
