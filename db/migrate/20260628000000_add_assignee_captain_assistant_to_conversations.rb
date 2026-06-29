class AddAssigneeCaptainAssistantToConversations < ActiveRecord::Migration[7.1]
  def change
    add_reference :conversations, :assignee_captain_assistant, type: :bigint, index: true
  end
end
