# Payload enxuto do Kanban SDR AI.
#
# Contém APENAS o que o card precisa para renderizar (ver kanban/config/cardFields.js).
# Mantém o mesmo formato `meta.sender` / `meta.assignee` do endpoint de lista para que
# o KanbanCard continue lendo os mesmos dot-paths, mas SEM as partes pesadas que causam
# N+1 no #index: `messages[]`, `last_non_activity_message` e `unread_count`.
ai_enabled_map = Finture::InboxConfig.ai_enabled_map(@conversations.map(&:inbox_id).uniq)
json.payload do
  json.array! @conversations do |conversation|
    json.id conversation.display_id
    json.inbox_id conversation.inbox_id
    json.status conversation.status
    json.priority conversation.priority
    json.labels conversation.cached_label_list_array
    json.custom_attributes conversation.custom_attributes
    json.finture_attendance Finture::AttendanceState.payload_for(conversation, ai_enabled: ai_enabled_map.fetch(conversation.inbox_id, false))
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
