# Home (Finture::HomeOverviewService), a tela de entrada de todos os usuários.
# Sem trava de papel e sem recorte por caixa: todo usuário da conta vê os
# números da conta inteira (Finture::HomeScopes#conversations_scope). O fuso é fixo em America/Sao_Paulo — "hoje", o período e
# os follow-ups do dia seguem o horário da operação, não o do servidor.
class Api::V1::Accounts::FintureHomeController < Api::V1::Accounts::BaseController
  around_action :use_home_time_zone

  def show
    render json: service.perform
  end

  # Lista que compõe um indicador, com os mesmos filtros do resumo.
  def list
    unless Finture::HomeOverviewService::METRICS.include?(params[:metric])
      return render json: { error: 'Indicador desconhecido' }, status: :unprocessable_entity
    end

    render json: service.drilldown(params[:metric])
  end

  private

  def use_home_time_zone(&)
    Time.use_zone(Finture::HomeOverviewService::TIME_ZONE, &)
  end

  def service
    Finture::HomeOverviewService.new(
      account: Current.account,
      current_user: Current.user,
      inbox_id: params[:inbox_id].presence,
      team_id: params[:team_id].presence,
      purpose: params[:purpose].presence,
      period: params[:period].presence
    )
  end
end
