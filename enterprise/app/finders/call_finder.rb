class CallFinder
  RESULTS_PER_PAGE = 25

  def initialize(current_user, current_account, params)
    @current_user = current_user
    @current_account = current_account
    @params = params
  end

  def perform
    @calls = @current_account.calls
    filter_by_visibility
    filter_by_status
    filter_by_direction
    filter_by_inbox
    filter_by_agent
    filter_by_date_range

    { calls: paginated_calls, count: @calls.count }
  end

  private

  # Non-admins only see calls they handled; admins see the whole account.
  def filter_by_visibility
    return if Current.account_user&.administrator?

    @calls = @calls.where(accepted_by_agent_id: @current_user.id)
  end

  def filter_by_status
    @calls = @calls.where(status: @params[:status]) if @params[:status].present?
  end

  def filter_by_direction
    @calls = @calls.where(direction: @params[:direction]) if @params[:direction].present?
  end

  def filter_by_inbox
    @calls = @calls.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
  end

  def filter_by_agent
    @calls = @calls.where(accepted_by_agent_id: @params[:agent_id]) if @params[:agent_id].present?
  end

  # since/until are unix timestamps, matching DateRangeHelper conventions.
  def filter_by_date_range
    return if @params[:since].blank? || @params[:until].blank?

    @calls = @calls.where(created_at: Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i))
  end

  def paginated_calls
    @calls.includes(:contact, :inbox, :conversation, :accepted_by_agent)
          .order(created_at: :desc)
          .page(@params[:page] || 1)
          .per(RESULTS_PER_PAGE)
  end
end
