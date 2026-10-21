# Dashboard SDR: métricas do funil por caixa (inbox_id) ou visão geral, num
# intervalo de datas. Liberado a agentes/admins, mas cada um só enxerga as
# conversas que o Kanban mostraria a ele (escopo em Finture::SdrShared); pedir
# uma caixa de que o agente não é membro devolve 403.
#
# Datas (buckets diários, "hoje" dos follow-ups) no fuso do navegador
# (`timezone`, nome IANA); sem ele ou inválido, America/Sao_Paulo. O servidor
# roda em UTC e a virada do dia caía às 21h no horário de Brasília.
#
# Duas visões (repaginação comercial x operacional):
# - view=commercial  → Finture::SdrCommercialReportService (conversão, perdas,
#   mix, tendência, velocidade), com janela de comparação ajustável.
# - view=operational → Finture::SdrOperationalReportService (follow-ups, SLA,
#   carga, aging, gargalo, leads parados).
# - default/legado   → Finture::SdrReportService (compatibilidade).
class Api::V1::Accounts::FintureSdrDashboardController < Api::V1::Accounts::BaseController
  DEFAULT_TIME_ZONE = 'America/Sao_Paulo'.freeze

  before_action :ensure_inbox_access
  around_action :use_report_time_zone

  def show
    render json: report
  end

  private

  def ensure_inbox_access
    return if params[:inbox_id].blank?
    return if Current.user&.assigned_inboxes&.exists?(id: params[:inbox_id])

    render json: { error: 'Caixa não permitida' }, status: :forbidden
  end

  def use_report_time_zone(&)
    Time.use_zone(report_time_zone, &)
  end

  def report_time_zone
    ActiveSupport::TimeZone[params[:timezone].to_s] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
  end

  def report
    case params[:view]
    when 'commercial'
      Finture::SdrCommercialReportService.new(
        **report_args,
        compare_since: params[:compare_since].presence,
        compare_until: params[:compare_until].presence
      ).perform
    when 'operational'
      Finture::SdrOperationalReportService.new(**report_args).perform
    else
      Finture::SdrReportService.new(**report_args).perform
    end
  end

  # current_user define o escopo de visibilidade (Finture::SdrShared).
  def report_args
    {
      account: Current.account,
      current_user: Current.user,
      inbox_id: params[:inbox_id].presence,
      since: params[:since].presence,
      until_at: params[:until].presence
    }
  end
end
