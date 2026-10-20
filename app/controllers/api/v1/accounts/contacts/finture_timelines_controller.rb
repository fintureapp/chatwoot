# Linha do tempo de um contato no Histórico do Kanban SDR: todas as conversas
# que o usuário enxerga, com abertura, fechamento e resumo de cada uma, mais o
# resumo rolante do contato (resumo_atendimentos). Também serve à triagem por IA
# (n8n), que consulta o histórico de quem já foi atendido.
class Api::V1::Accounts::Contacts::FintureTimelinesController < Api::V1::Accounts::Contacts::BaseController
  def show
    @timeline = Finture::ContactTimelineService.new(
      contact: @contact, user: Current.user, account: Current.account
    ).perform
  end
end
