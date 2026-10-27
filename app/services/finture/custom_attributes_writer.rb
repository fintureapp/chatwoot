# Escrita do POST conversations/:id/custom_attributes, que substitui o hash
# inteiro — e fluxos do n8n regravam a cópia que leram antes. O
# `modo_atendimento` é do servidor (Finture::AttendanceModeService): o valor
# atual é sempre preservado, então hash velho não desfaz um "Assumir" e devolver
# à IA só pelo botão. Pedido de 'humano' (handoff antigo do n8n) escala pelo
# serviço depois de gravar o resto.
class Finture::CustomAttributesWriter
  MODE_KEY = Finture::AttendanceState::MODE_KEY

  pattr_initialize [:conversation!, :user]

  def assign!(incoming)
    incoming = incoming.to_h
    requested = incoming[MODE_KEY].to_s.strip.downcase
    conversation.custom_attributes = preserve_mode(incoming)
    conversation.save!
    return unless requested == 'humano'

    Finture::AttendanceModeService.new(conversation: conversation).escalate!(source: 'legacy_api', user: user)
  end

  private

  def preserve_mode(incoming)
    current = (conversation.custom_attributes || {})[MODE_KEY]
    current.nil? ? incoming.except(MODE_KEY) : incoming.merge(MODE_KEY => current)
  end
end
