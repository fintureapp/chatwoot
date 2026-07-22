# Follow-ups com prazo do card (Fase 1 CRM Finture). Toda mutação ressincroniza
# o espelho sdr_follow_up_due_at nos custom_attributes da conversa — é ele que
# alimenta o badge de vencido no board e o broadcast em tempo real.
class Api::V1::Accounts::Conversations::FintureFollowUpsController < Api::V1::Accounts::Conversations::BaseController
  before_action :follow_up, only: [:update, :destroy]

  def index
    render json: { follow_ups: scoped_follow_ups.order(:due_at).map { |item| serialize(item) } }
  end

  def create
    item = scoped_follow_ups.create!(
      account_id: @conversation.account_id,
      user: Current.user,
      **follow_up_params
    )
    Finture::FollowUp.sync_mirror!(@conversation)
    render json: serialize(item)
  end

  def update
    attrs = follow_up_params
    attrs[:completed_at] = params[:completed] ? Time.current : nil if params.key?(:completed)
    @follow_up.update!(attrs)
    Finture::FollowUp.sync_mirror!(@conversation)
    render json: serialize(@follow_up)
  end

  def destroy
    @follow_up.destroy!
    Finture::FollowUp.sync_mirror!(@conversation)
    head :ok
  end

  private

  def follow_up
    @follow_up = scoped_follow_ups.find(params[:id])
  end

  def scoped_follow_ups
    Finture::FollowUp.where(conversation_id: @conversation.id)
  end

  def follow_up_params
    params.permit(:title, :notes, :due_at).to_h.symbolize_keys
  end

  def serialize(item)
    item.slice(:id, :title, :notes, :due_at, :completed_at, :created_at)
        .merge(user_name: item.user&.available_name)
  end
end
