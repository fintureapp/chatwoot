# Desfecho do card do Kanban SDR (ganho/perdido/reabrir), marcado dentro do card.
# Delega ao Finture::OutcomeService (registra a transição + espelha sdr_outcome).
class Api::V1::Accounts::Conversations::FintureOutcomesController < Api::V1::Accounts::Conversations::BaseController
  def update
    unless Finture::OutcomeService::KINDS.include?(params[:kind])
      return render json: { error: 'Desfecho inválido.' }, status: :unprocessable_entity
    end

    Finture::OutcomeService.new(
      conversation: @conversation,
      kind: params[:kind],
      user: Current.user,
      reason: params[:reason],
      comment: params[:comment]
    ).perform
    render json: { custom_attributes: @conversation.reload.custom_attributes }
  end
end
