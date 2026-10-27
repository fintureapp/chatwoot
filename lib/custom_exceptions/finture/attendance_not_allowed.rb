# Troca de modo recusada por regra (caixa sem IA, conversa resolvida, motivo
# ausente, já está com a IA...). `key` aponta para finture.attendance.errors.
class CustomExceptions::Finture::AttendanceNotAllowed < CustomExceptions::Base
  def message
    I18n.t("finture.attendance.errors.#{@data[:key]}")
  end

  def http_status
    422
  end
end
