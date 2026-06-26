json.array! @accounts do |account|
  json.id account.id
  json.name account.name
  json.created_at account.created_at
  json.updated_at account.updated_at
  json.status account.status
  json.plan_name account.custom_attributes['plan_name']
  json.custom_attributes account.custom_attributes
  json.limits account.limits
  json.marketing_attribution account.internal_attributes['marketing_attribution']
end
