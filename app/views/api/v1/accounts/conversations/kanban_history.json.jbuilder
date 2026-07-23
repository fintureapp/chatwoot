# Histórico do Kanban SDR: leads já fechados (ganho/perdido) de uma caixa. Mesmo
# payload enxuto do board — o card lê sdr_outcome/_at, sdr_lost_reason e
# valor_potencial dos custom_attributes.
json.payload do
  json.array! @conversations do |conversation|
    json.id conversation.display_id
    json.inbox_id conversation.inbox_id
    json.status conversation.status
    json.priority conversation.priority
    json.labels conversation.cached_label_list_array
    json.custom_attributes conversation.custom_attributes
    json.created_at conversation.created_at.to_i
    json.last_activity_at conversation.last_activity_at.to_i
    json.timestamp conversation.last_activity_at.to_i
    json.waiting_since conversation.waiting_since.to_i

    json.meta do
      json.sender do
        contact = conversation.contact
        json.id contact&.id
        json.name contact&.name
        json.email contact&.email
        json.phone_number contact&.phone_number
        json.thumbnail contact&.avatar_url
      end
      if conversation.assignee.present?
        json.assignee do
          json.id conversation.assignee.id
          json.name conversation.assignee.name
          json.thumbnail conversation.assignee.avatar_url
        end
      end
    end
  end
end
