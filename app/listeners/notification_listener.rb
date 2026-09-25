class NotificationListener < BaseListener
  # Label applied by Bia/n8n/agents to hand a conversation off to a human.
  HUMAN_HANDOFF_LABEL = 'atendimento_humano'.freeze

  def conversation_bot_handoff(event)
    conversation, account = extract_conversation_and_account(event)
    return if conversation.pending?

    conversation.inbox.members.each do |agent|
      NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: agent,
        account: account,
        primary_actor: conversation
      ).perform
    end
  end

  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    return if conversation.pending?

    conversation.inbox.members.each do |agent|
      NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: agent,
        account: account,
        primary_actor: conversation
      ).perform
    end
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    assignee = conversation.assignee

    # NOTE:  The issue was that when a team change results in an assignee being set to nil,
    # the system was still trying to create a notification about the assignment change,
    # but there was no assignee to notify, causing potential issues in the notification system.
    # We need to debug this properly, but for now no need to pollute the jobs
    return if assignee.blank?
    return if event.data[:notifiable_assignee_change].blank?
    return if conversation.pending?

    NotificationBuilder.new(
      notification_type: 'conversation_assignment',
      user: assignee,
      account: account,
      primary_actor: conversation
    ).perform
  end

  # Notify every member of the team when a conversation is assigned to a team.
  # Covers Bia handoffs, n8n follow-ups and manual team assignments. Any duplicate
  # against conversation_assignment (when the assignee is also a team member) is
  # collapsed by Notification::RemoveDuplicateNotificationJob.
  def team_changed(event)
    conversation, account = extract_conversation_and_account(event)
    team = conversation.team

    return if team.blank?
    return if conversation.pending?

    team.members.each do |agent|
      NotificationBuilder.new(
        notification_type: 'team_assignment',
        user: agent,
        account: account,
        primary_actor: conversation
      ).perform
    end
  end

  # Handoff by label: when `atendimento_humano` is applied to a conversation that has
  # no team assigned, surface it to the inbox members as a new conversation pending
  # human attention (same treatment as a bot handoff / new conversation).
  def conversation_updated(event)
    conversation, account = extract_conversation_and_account(event)

    return unless human_handoff_label_added?(event)
    return if conversation.team_id.present?
    return if conversation.assignee_id.present?
    return if conversation.pending?

    conversation.inbox.members.each do |agent|
      NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: agent,
        account: account,
        primary_actor: conversation
      ).perform
    end
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]

    Messages::MentionService.new(message: message).perform
    Messages::NewMessageNotificationService.new(message: message).perform
  end

  private

  def human_handoff_label_added?(event)
    changed_attributes = event.data[:changed_attributes]
    return false if changed_attributes.blank?

    label_change = changed_attributes['label_list'] || changed_attributes[:label_list]
    previous_labels, current_labels = label_change
    return false unless previous_labels.is_a?(Array) && current_labels.is_a?(Array)

    (current_labels - previous_labels).include?(HUMAN_HANDOFF_LABEL)
  end
end
