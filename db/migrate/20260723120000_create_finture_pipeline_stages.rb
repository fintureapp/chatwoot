# Etapas configuráveis do funil do Kanban SDR, POR CAIXA (inbox_id). A 1ª etapa
# (Lead Identificado) é sempre `locked: true` e não pode ser renomeada de slug,
# movida da 1ª posição nem removida. `slug` é o valor estável persistido em
# conversation.custom_attributes.sdr_stage; guardá-lo como string (e não FK)
# preserva o histórico das transições após rename/exclusão da etapa. Aditivo,
# FK cascade → exclusão LGPD limpa, zero toque no core.
class CreateFinturePipelineStages < ActiveRecord::Migration[7.1]
  def change
    create_table :finture_pipeline_stages do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.string :color, null: false, default: 'slate'
      t.boolean :locked, null: false, default: false
      t.timestamps
    end
    add_index :finture_pipeline_stages, [:inbox_id, :slug], unique: true
    add_index :finture_pipeline_stages, [:inbox_id, :position]
    add_index :finture_pipeline_stages, :account_id
    add_foreign_key :finture_pipeline_stages, :inboxes, on_delete: :cascade
    add_foreign_key :finture_pipeline_stages, :accounts, on_delete: :cascade
  end
end
