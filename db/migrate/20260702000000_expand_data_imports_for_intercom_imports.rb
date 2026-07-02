class ExpandDataImportsForIntercomImports < ActiveRecord::Migration[7.1]
  def change
    change_table :data_imports, bulk: true do |t|
      t.string :name
      t.string :source_type
      t.string :source_provider
      t.jsonb :import_types, default: [], null: false
      t.integer :initiated_by_id
      t.bigint :integration_hook_id
      t.integer :target_inbox_id
      t.jsonb :config, default: {}, null: false
      t.jsonb :source_metadata, default: {}, null: false
      t.jsonb :stats, default: {}, null: false
      t.jsonb :cursor, default: {}, null: false
      t.jsonb :routing_rules, default: {}, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :abandoned_at
      t.datetime :last_error_at
    end

    add_index :data_imports, :initiated_by_id
    add_index :data_imports, :integration_hook_id
    add_index :data_imports, :source_provider
    add_index :data_imports, :target_inbox_id
  end
end
