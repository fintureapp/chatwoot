# Follow-ups com prazo do Kanban SDR (Fase 1 CRM Finture): substitui o texto
# livre sdr_next_action por cadência cobrável (criar/concluir, vencido em
# destaque no board). Índice parcial cobre a consulta "próximo follow-up
# aberto" que alimenta o espelho sdr_follow_up_due_at.
class CreateFintureFollowUps < ActiveRecord::Migration[7.1]
  def change
    create_table :finture_follow_ups do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :user_id
      t.string :title, null: false
      t.text :notes
      t.datetime :due_at, null: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :finture_follow_ups, :account_id
    add_index :finture_follow_ups, [:conversation_id, :due_at]
    add_index :finture_follow_ups, :due_at, where: 'completed_at IS NULL', name: 'index_finture_follow_ups_open_due'
    add_foreign_key :finture_follow_ups, :conversations, on_delete: :cascade
    add_foreign_key :finture_follow_ups, :accounts, on_delete: :cascade
    add_foreign_key :finture_follow_ups, :users, on_delete: :nullify
  end
end
