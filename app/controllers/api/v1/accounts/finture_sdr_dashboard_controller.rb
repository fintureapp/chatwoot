# Dashboard SDR: métricas do funil por caixa (inbox_id) ou visão geral, num
# intervalo de datas. Leitura liberada a agentes/admins (só agrega).
#
# Duas visões (repaginação comercial x operacional):
# - view=commercial  → Finture::SdrCommercialReportService (conversão, perdas,
#   mix, tendência, velocidade), com janela de comparação ajustável.
# - view=operational → Finture::SdrOperationalReportService (follow-ups, SLA,
#   carga, aging, gargalo, leads parados).
# - default/legado   → Finture::SdrReportService (compatibilidade).
class Api::V1::Accounts::FintureSdrDashboardController < Api::V1::Accounts::BaseController
  def show
    render json: report
  end

  private

  def report
    case params[:view]
    when 'commercial'
      Finture::SdrCommercialReportService.new(
        account: Current.account,
        inbox_id: params[:inbox_id].presence,
        since: params[:since].presence,
        until_at: params[:until].presence,
        compare_since: params[:compare_since].presence,
        compare_until: params[:compare_until].presence
      ).perform
    when 'operational'
      Finture::SdrOperationalReportService.new(
        account: Current.account,
        inbox_id: params[:inbox_id].presence,
        since: params[:since].presence,
        until_at: params[:until].presence
      ).perform
    else
      Finture::SdrReportService.new(
        account: Current.account,
        inbox_id: params[:inbox_id].presence,
        since: params[:since].presence,
        until_at: params[:until].presence
      ).perform
    end
  end
end
