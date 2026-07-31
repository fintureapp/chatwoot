class AutoAssignment::AgentAssignmentService
  # Allowed agent ids: array
  # This is the list of agents from which an agent can be assigned to this conversation
  # examples: Agents with assignment capacity, Agents who are members of a team etc
  pattr_initialize [:conversation!, :allowed_agent_ids!]

  def find_assignee
    round_robin_manage_service.available_agent(allowed_agent_ids: assignment_candidate_ids)
  end

  def perform
    new_assignee = find_assignee
    conversation.update(assignee: new_assignee) if new_assignee
  end

  private

  # Round robin over the online agents whenever at least one is online. When
  # nobody is online we still distribute, using the eligible offline agents,
  # so conversations don't sit unassigned outside working hours.
  def assignment_candidate_ids
    allowed_online_agent_ids.presence || allowed_eligible_agent_ids
  end

  def online_agent_ids
    online_agents = OnlineStatusTracker.get_available_users(conversation.account_id)
    return [] if online_agents.blank?

    online_agents.select { |_key, value| value.eql?('online') }.keys
  end

  # Agents that may be assigned regardless of presence. Intersected here rather
  # than trusted from the caller so the eligibility rules hold on every path.
  def allowed_eligible_agent_ids
    # the ids are compared as strings, since the online ids come from redis
    @allowed_eligible_agent_ids ||= eligible_agent_ids & allowed_agent_ids.to_a.map(&:to_s)
  end

  def eligible_agent_ids
    conversation.inbox.assignment_eligible_members.map { |member| member.user_id.to_s }
  end

  def allowed_online_agent_ids
    @allowed_online_agent_ids ||= online_agent_ids & allowed_eligible_agent_ids
  end

  def round_robin_manage_service
    @round_robin_manage_service ||= AutoAssignment::InboxRoundRobinService.new(inbox: conversation.inbox)
  end

  def round_robin_key
    format(::Redis::Alfred::ROUND_ROBIN_AGENTS, inbox_id: conversation.inbox_id)
  end
end
