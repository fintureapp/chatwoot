module InboxAgentAvailability
  extend ActiveSupport::Concern

  # Members that are allowed to receive an auto assignment at all.
  #
  # Presence is deliberately NOT part of this scope: callers pick the online
  # subset first and fall back to this pool when nobody is online.
  #
  # Excluded here: agents without access to the inbox (they are not inbox
  # members), agents that no longer belong to the account, and agents that
  # cannot sign in yet (pending invite, confirmable is enforced on login).
  #
  # This is the single place to narrow the pool further. Per-agent schedules
  # ("escala") and leave flags ("afastado") belong here.
  #
  # Not to be confused with Inbox#assignable_agents, which lists the users an
  # operator may pick from when assigning by hand.
  def assignment_eligible_members
    inbox_members
      .joins(user: :account_users)
      .where(account_users: { account_id: account_id })
      .where.not(users: { confirmed_at: nil })
      .includes(:user)
  end

  # Online subset of the assignable pool. Use this when live presence is the
  # actual requirement (e.g. ringing agents on an incoming call), not when
  # picking an assignee.
  def available_agents
    online_agent_ids = fetch_online_agent_ids
    return inbox_members.none if online_agent_ids.empty?

    assignment_eligible_members.where(users: { id: online_agent_ids })
  end

  # Distribution rule: while at least one candidate is online, assign only among
  # those; otherwise fall back to the whole eligible pool so conversations don't
  # sit unassigned outside working hours.
  def prioritize_online_agents(members)
    online_agent_ids = fetch_online_agent_ids
    return members.to_a if online_agent_ids.empty?

    online_members = members.select { |member| online_agent_ids.include?(member.user_id) }
    online_members.presence || members.to_a
  end

  def member_ids_with_assignment_capacity
    assignment_eligible_members.map(&:user_id)
  end

  private

  def fetch_online_agent_ids
    OnlineStatusTracker.get_available_users(account_id)
                       .select { |_key, value| value.eql?('online') }
                       .keys
                       .map(&:to_i)
  end
end

InboxAgentAvailability.prepend_mod_with('InboxAgentAvailability')
