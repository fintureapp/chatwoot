# Agendamento pode ser texto livre OU template aprovado do WhatsApp. Com
# template, `template_params` guarda o mesmo payload que a caixa de resposta
# manda ao enviar um template (name, category, language, namespace,
# processed_params) e `content` fica com o texto renderizado (prévia/histórico).
class AddTemplateParamsToFintureScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :finture_scheduled_messages, :template_params, :jsonb
  end
end
