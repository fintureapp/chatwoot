# Mensagem do bot recusada pelo Finture::BotMessageGuard (alguém assumiu ou o
# modo mudou desde que o bot leu o estado). Vira 409 para o n8n parar o fluxo.
class CustomExceptions::Finture::BotMessageBlocked < CustomExceptions::Base
  def state
    @data[:state]
  end

  def message
    I18n.t('finture.attendance.errors.bot_blocked')
  end

  def http_status
    409
  end
end
