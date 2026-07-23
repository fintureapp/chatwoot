# Mudança de etapa do card no servidor — usado pelo board (source=agent) e pelo
# SDR IA no n8n (source=n8n). Delega validação/registro da transição e o espelho
# de sdr_stage ao Finture::StageChangeService. Autenticação do n8n é o token de
# API padrão de um usuário agente (mesmo mecanismo da cotação).
class Api::V1::Accounts::Conversations::FintureStagesController < Api::V1::Accounts::Conversations::BaseController
  def update
    Finture::StageChangeService.new(
      conversation: @conversation,
      to_stage: params[:stage].to_s,
      source: source_param,
      user: Current.user
    ).perform
    render json: { custom_attributes: @conversation.reload.custom_attributes }
  end

  private

  def source_param
    %w[agent n8n].include?(params[:source]) ? params[:source] : 'agent'
  end
end
