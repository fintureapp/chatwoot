# Registro server-side de cada mudança de etapa / desfecho do Kanban SDR
# (append-only). É a base confiável do Dashboard SDR (tempo médio por etapa,
# conversão) e do histórico do card — substitui o log frágil em
# custom_attributes.sdr_history (client-side, teto 20). `to_stage_label` congela
# o nome exibido para o histórico continuar legível mesmo após rename/exclusão
# da etapa. `kind`: stage_change | won | lost | reopen.
class CreateFintureStageTransitions < ActiveRecord::Migration[7.1]
  def change
    create_table :finture_stage_transitions do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :inbox_id
      t.bigint :user_id
      t.string :from_stage
      t.string :to_stage, null: false
      t.string :to_stage_label
      t.string :kind, null: false, default: 'stage_change'
      t.string :reason
      t.text :comment
      t.string :source, null: false, default: 'agent'
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :finture_stage_transitions, [:conversation_id, :occurred_at], name: 'index_finture_stage_transitions_on_conv_occurred'
    add_index :finture_stage_transitions, [:account_id, :inbox_id, :occurred_at], name: 'index_finture_stage_transitions_on_acct_inbox_occurred'
    add_index :finture_stage_transitions, [:account_id, :to_stage], name: 'index_finture_stage_transitions_on_acct_to_stage'
    add_foreign_key :finture_stage_transitions, :conversations, on_delete: :cascade
    add_foreign_key :finture_stage_transitions, :accounts, on_delete: :cascade
    add_foreign_key :finture_stage_transitions, :inboxes, on_delete: :nullify
    add_foreign_key :finture_stage_transitions, :users, on_delete: :nullify
  end
end
