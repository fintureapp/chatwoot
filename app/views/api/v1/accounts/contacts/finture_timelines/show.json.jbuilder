# Linha do tempo do contato (Histórico do Kanban SDR e triagem IA). Datas em
# epoch (segundos), como no restante do payload do Kanban.
contact = @timeline[:contact]
contact_attrs = contact.custom_attributes || {}

json.contact do
  json.id contact.id
  json.name contact.name
  json.email contact.email
  json.phone_number contact.phone_number
  json.thumbnail contact.avatar_url
  json.resumo_atendimentos contact_attrs['resumo_atendimentos']
  json.resumo_atendimentos_em contact_attrs['resumo_atendimentos_em']
end

json.payload do
  json.array! @timeline[:entries] do |entry|
    conversation = entry[:conversation]
    attrs = conversation.custom_attributes || {}

    json.id conversation.display_id
    json.inbox_id conversation.inbox_id
    json.inbox_name conversation.inbox&.name
    json.kanban_type entry[:kanban_type]
    json.status conversation.status
    json.created_at conversation.created_at.to_i
    json.closed_at entry[:closed_at]&.to_i
    json.last_activity_at conversation.last_activity_at.to_i
    json.outcome attrs['sdr_outcome']
    json.lost_reason attrs['sdr_lost_reason']
    json.valor_potencial attrs['valor_potencial']
    json.stage attrs['sdr_stage']
    json.resumo attrs['sdr_resumo']
    json.resumo_em attrs['sdr_resumo_em']
    json.labels conversation.cached_label_list_array
    json.assignee_name conversation.assignee&.name
  end
end
