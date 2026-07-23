# Dashboard SDR: métricas do funil por caixa (inbox_id) ou visão geral, num
# intervalo de datas. Leitura liberada a agentes/admins (só agrega). Cálculo no
# Finture::SdrReportService.
class Api::V1::Accounts::FintureSdrDashboardController < Api::V1::Accounts::BaseController
  def show
    render json: Finture::SdrReportService.new(
      account: Current.account,
      inbox_id: params[:inbox_id].presence,
      since: params[:since].presence,
      until_at: params[:until].presence
    ).perform
  end
end
