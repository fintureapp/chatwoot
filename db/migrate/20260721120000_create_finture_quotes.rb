# Cotação estruturada do lead (Fase 1 CRM Finture): 1 cotação por conversa —
# no Kanban SDR o card É a conversation, então a cotação estende a conversa.
# FK com cascade no banco (sem has_one no core) mantém o fork aditivo e a
# exclusão LGPD limpa. `data` guarda a seção do produto (faixas ANS etc.);
# validação de estrutura fica no model Finture::Quote.
class CreateFintureQuotes < ActiveRecord::Migration[7.1]
  def change
    create_table :finture_quotes do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.string :product_type, null: false # saude_pme | consorcio | seguros | credito
      t.jsonb :data, null: false, default: {}
      t.decimal :total_value, precision: 12, scale: 2 # reais, mesma unidade do custom attribute valor_potencial
      t.string :source, null: false, default: 'agent' # agent | n8n (último gravador)
      t.timestamps
    end
    add_index :finture_quotes, :conversation_id, unique: true
    add_index :finture_quotes, :account_id
    add_foreign_key :finture_quotes, :conversations, on_delete: :cascade
    add_foreign_key :finture_quotes, :accounts, on_delete: :cascade
  end
end
