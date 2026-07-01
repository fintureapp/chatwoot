class CreateCaptainConversationFacts < ActiveRecord::Migration[7.1]
  def change
    create_captain_conversation_facts_table
    add_captain_conversation_facts_indexes
  end

  private

  def create_captain_conversation_facts_table
    create_table :captain_conversation_facts do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :assistant_id, null: false
      t.bigint :inbox_id, null: false
      t.datetime :first_captain_message_at
      t.datetime :last_captain_message_at
      t.datetime :captain_resolved_at
      t.datetime :captain_handed_off_at
      t.datetime :first_human_reply_after_captain_at
      t.datetime :reopened_after_captain_resolution_at
      t.bigint :csat_response_id
      t.integer :csat_rating
      t.datetime :csat_submitted_at

      t.timestamps
    end
  end

  def add_captain_conversation_facts_indexes
    add_index :captain_conversation_facts, :account_id
    add_index :captain_conversation_facts, :conversation_id, unique: true
    add_index :captain_conversation_facts, [:account_id, :assistant_id, :first_captain_message_at],
              name: 'idx_captain_facts_on_account_assistant_first_message'
    add_index :captain_conversation_facts, [:account_id, :captain_resolved_at],
              name: 'idx_captain_facts_on_account_resolved_at'
    add_index :captain_conversation_facts, [:account_id, :captain_handed_off_at],
              name: 'idx_captain_facts_on_account_handed_off_at'
    add_index :captain_conversation_facts, [:account_id, :csat_submitted_at],
              name: 'idx_captain_facts_on_account_csat_submitted_at'
  end
end
