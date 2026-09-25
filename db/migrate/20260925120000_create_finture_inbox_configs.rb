# Classificação de negócio da caixa (inbox) para o Kanban SDR: 'comercial' ou
# 'operacional'. Define o funil semeado (etapas comerciais x operacionais), como
# o card sai do board ativo (desfecho ganho/perdido x resolver nativo) e a visão
# padrão do Dashboard. Uma linha por caixa; sem linha => 'comercial' (default,
# preserva o comportamento atual). Aditivo, FK cascade → LGPD limpa, zero toque
# no core (a tabela inboxes permanece intocada).
class CreateFintureInboxConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :finture_inbox_configs do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :kanban_type, null: false, default: 'comercial'
      t.timestamps
    end
    add_index :finture_inbox_configs, :inbox_id, unique: true
    add_index :finture_inbox_configs, :account_id
    add_foreign_key :finture_inbox_configs, :inboxes, on_delete: :cascade
    add_foreign_key :finture_inbox_configs, :accounts, on_delete: :cascade
  end
end
