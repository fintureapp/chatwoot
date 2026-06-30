class CreateCaptainUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_usages do |t|
      t.references :account, null: false
      t.references :assistant, null: false
      t.integer :usage_type, null: false
      # Usage is binned into 15-minute UTC buckets so it can be re-sliced into
      # any caller timezone (including :45 offset zones). Do not widen to hourly.
      t.datetime :bucket_started_at, null: false
      t.integer :credits_used, null: false, default: 0

      t.timestamps
    end

    add_index :captain_usages,
              [:account_id, :assistant_id, :usage_type, :bucket_started_at],
              unique: true,
              name: 'index_captain_usages_unique_bucket'
  end
end
