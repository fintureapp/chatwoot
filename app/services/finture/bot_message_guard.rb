# Trava do envio do bot (n8n). O bot manda em content_attributes a revisão do
# modo de atendimento que leu no início da execução; com a conversa travada
# (mesma trava do Finture::AttendanceModeService), a mensagem só é criada se:
#   - o modo é 'ia' e a revisão não mudou; ou
#   - é a confirmação do handoff: modo 'humano' feito pelo próprio bot, mesma
#     revisão (nenhum humano agiu no meio).
# Caso contrário, nada é criado e o n8n recebe 409. Mensagem SEM a revisão segue
# o caminho de sempre (compatível com os fluxos antigos); nota privada nunca é
# barrada (não chega ao cliente).
class Finture::BotMessageGuard
  REVISION_KEY = 'finture_bot_revision'.freeze

  # Revisão enviada pelo bot, ou nil quando a mensagem não pediu a trava.
  def self.revision_from(params)
    return if ActiveModel::Type::Boolean.new.cast(params[:private])

    value = content_attributes(params[:content_attributes])[REVISION_KEY]
    value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
  end

  # Chamar com a conversa já travada.
  def self.allow!(conversation, revision)
    state = Finture::AttendanceState.for(conversation)
    return if state.revision == revision && (state.ia? || state.changed_by_bot?)

    raise CustomExceptions::Finture::BotMessageBlocked.new(state: state)
  end

  def self.content_attributes(raw)
    raw = JSON.parse(raw) if raw.is_a?(String)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.stringify_keys : {}
  rescue JSON::ParserError
    {}
  end
  private_class_method :content_attributes
end
