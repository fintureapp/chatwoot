class RoomChannel < ApplicationCable::Channel
  # Server-side heartbeat: renews presence while the WebSocket connection is alive,
  # independent of the browser tab being visible/foreground. This prevents an agent
  # from expiring in Redis (and dropping out of routing) when the tab throttles its
  # own timers in the background.
  PRESENCE_HEARTBEAT_INTERVAL = ENV.fetch('PRESENCE_HEARTBEAT_INTERVAL', 15).to_i.seconds

  periodically :refresh_presence, every: PRESENCE_HEARTBEAT_INTERVAL

  def subscribed
    # TODO: should we only do ensure stream  if current account is present?
    # for now going ahead with guard clauses in update_subscription and broadcast_presence
    current_user
    current_account
    ensure_stream
    update_subscription
    broadcast_presence
  end

  def update_presence
    update_subscription
    broadcast_presence
  end

  private

  # Runs on the server timer for as long as the connection is subscribed. Renewing the
  # Redis presence score is enough to keep the agent online; connected peers pick up the
  # refreshed presence on their next heartbeat snapshot. Scoped to agents so contact
  # presence keeps relying on the widget ping window as before.
  def refresh_presence
    return unless @current_user.is_a?(User)

    update_subscription
  end

  def broadcast_presence
    return if @current_account.blank?

    data = { account_id: @current_account.id, users: ::OnlineStatusTracker.get_available_users(@current_account.id) }
    data[:contacts] = ::OnlineStatusTracker.get_available_contacts(@current_account.id) if @current_user.is_a? User
    ActionCable.server.broadcast(pubsub_token, { event: 'presence.update', data: data })
  end

  def ensure_stream
    stream_from pubsub_token
    stream_from "account_#{@current_account.id}" if @current_account.present? && @current_user.is_a?(User)
  end

  def update_subscription
    return if @current_account.blank?

    ::OnlineStatusTracker.update_presence(@current_account.id, @current_user.class.name, @current_user.id)
  end

  def pubsub_token
    @pubsub_token ||= params[:pubsub_token]
  end

  def current_user
    @current_user ||= if params[:user_id].blank?
                        ContactInbox.find_by!(pubsub_token: pubsub_token).contact
                      else
                        User.find_by!(pubsub_token: pubsub_token, id: params[:user_id])
                      end
  end

  def current_account
    return if current_user.blank?

    @current_account ||= if @current_user.is_a? Contact
                           @current_user.account
                         else
                           @current_user.accounts.find(params[:account_id])
                         end
  end
end
