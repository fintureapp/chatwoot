# O modo de atendimento mudou desde a leitura (revisão divergente): outra pessoa
# (ou o bot) agiu antes. Vira 409 com o estado atual para a tela se atualizar.
class CustomExceptions::Finture::AttendanceConflict < CustomExceptions::Base
  def state
    @data[:state]
  end

  def conversation
    @data[:conversation]
  end

  def message
    name = state.changed_by_name.presence || I18n.t('finture.attendance.actors.system')
    time = state.changed_at&.in_time_zone('America/Sao_Paulo')&.strftime('%H:%M')
    key = state.human? ? 'conflict_human' : 'conflict_ai'
    I18n.t("finture.attendance.errors.#{key}", name: name, time: time || '-')
  end

  def http_status
    409
  end
end
