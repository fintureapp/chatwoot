class Conversations::AssignmentService
  def initialize(conversation:, assignee_id:, assignee_type: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
  end

  def perform
    return assign_agent_bot if agent_bot_assignment?
    return assign_captain_assistant if captain_assistant_assignment?

    assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type

  def assign_agent
    captain_owned = conversation.assignee_captain_assistant_id.present?
    conversation.assignee = assignee
    conversation.assignee_agent_bot = nil
    conversation.assignee_captain_assistant = nil
    conversation.status = :open if assignee.present? && captain_owned && conversation.pending?
    conversation.save!
    assignee
  end

  def assign_agent_bot
    return unless agent_bot

    conversation.assignee = nil
    conversation.assignee_agent_bot = agent_bot
    conversation.assignee_captain_assistant = nil
    conversation.save!
    agent_bot
  end

  def assign_captain_assistant
    return unless captain_assistant

    conversation.assignee = nil
    conversation.assignee_agent_bot = nil
    conversation.assignee_captain_assistant = captain_assistant
    conversation.status = :pending
    conversation.save!
    captain_assistant
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  def agent_bot
    @agent_bot ||= AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
  end

  def captain_assistant
    @captain_assistant ||= Captain::Assistant.for_account(conversation.account_id).find_by(id: assignee_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end

  def captain_assistant_assignment?
    assignee_type.to_s == 'CaptainAssistant'
  end
end
