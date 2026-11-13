# Central de Demandas (Chatwoot → HUB Finture) — estado do envio por conversa.
#
# finture_demanda_syncs: 1 linha por conversa operacional que virou demanda no
# HUB (etapa `em_atendimento` E responsável). Guarda o id devolvido pelo HUB, o
# hash do último payload enviado (evita reenvio idêntico) e o resultado da
# última tentativa. Fica FORA de custom_attributes de propósito: fluxos do n8n
# regravam esse hash inteiro com cópia velha, e gravar nele dispararia o
# próprio listener (conversation_updated) que alimenta esta integração.
class CreateFintureDemandaSyncs < ActiveRecord::Migration[7.1]
  def change
    create_table :finture_demanda_syncs do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :inbox_id
      t.string :external_id, null: false
      t.string :hub_demanda_id
      t.string :status, null: false, default: 'pending'
      t.string :last_event
      t.string :last_payload_hash
      t.datetime :last_sent_at
      t.text :last_error
      t.integer :attempts, null: false, default: 0
      t.timestamps
    end
    add_index :finture_demanda_syncs, :conversation_id, unique: true
    add_index :finture_demanda_syncs, :external_id, unique: true
    add_index :finture_demanda_syncs, [:account_id, :status]
    add_foreign_key :finture_demanda_syncs, :conversations, on_delete: :cascade
    add_foreign_key :finture_demanda_syncs, :accounts, on_delete: :cascade
  end
end
