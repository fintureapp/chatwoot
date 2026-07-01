class AddActorToReportingEvents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :reporting_events, :actor_type, :string
    add_column :reporting_events, :actor_id, :bigint

    add_index :reporting_events,
              [:account_id, :actor_type, :actor_id, :name, :created_at],
              name: 'idx_reporting_events_on_account_actor_name_created',
              algorithm: :concurrently
  end
end
