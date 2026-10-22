# Modo de atendimento da conversa (IA x humano) — botões "Assumir conversa" /
# "Devolver à IA" do painel e handoff da triagem do n8n. Permissão: quem enxerga
# a conversa (BaseController autoriza :show?), ou seja, qualquer membro da caixa.
# Toda resposta traz o estado atual; conflito de revisão vira 409 com o estado
# para a tela se atualizar sem confirmar nada falso.
class Api::V1::Accounts::Conversations::FintureAttendancesController < Api::V1::Accounts::Conversations::BaseController
  rescue_from CustomExceptions::Finture::AttendanceConflict, with: :render_conflict
  rescue_from CustomExceptions::Finture::AttendanceNotAllowed, with: :render_not_allowed

  def show
    render_state
  end

  def take_over
    service.take_over!(user: Current.user, reason: params[:reason], expected_revision: params[:expected_revision])
    render_state
  end

  def return_to_ai
    service.return_to_ai!(
      user: Current.user, reason: params[:reason], pending_notes: params[:pending_notes],
      expected_revision: params[:expected_revision]
    )
    render_state
  end

  # Usado pelo n8n no lugar de "Set Custom Attr Humano" + "POST Labels Handoff".
  # Devolve a revisão nova, que o bot usa para enviar a confirmação ao cliente.
  def bot_handoff
    service.bot_handoff!(reason: params[:reason], triage: triage_params, expected_revision: params[:expected_revision])
    render_state
  end

  private

  def service
    Finture::AttendanceModeService.new(conversation: @conversation)
  end

  def triage_params
    params.fetch(:triage, {}).permit(:tipo, :produto, :descricao, :time).to_h.compact_blank
  end

  def render_state
    @conversation.reload
    render json: { attendance: Finture::AttendanceState.payload_for(@conversation), assignee_id: @conversation.assignee_id }
  end

  def render_conflict(exception)
    @conversation.reload
    render json: { error: exception.message, attendance: Finture::AttendanceState.payload_for(@conversation) }, status: :conflict
  end

  def render_not_allowed(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end
