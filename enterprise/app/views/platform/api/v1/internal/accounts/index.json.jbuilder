json.array! @accounts do |account|
  json.id account.id
  json.name account.name
  json.created_at account.created_at
  json.updated_at account.updated_at
  json.status account.status
  json.plan_name account.custom_attributes['plan_name']
  json.stripe_customer_id account.custom_attributes['stripe_customer_id']
  json.stripe_price_id account.custom_attributes['stripe_price_id']
  json.stripe_product_id account.custom_attributes['stripe_product_id']
  json.subscription_status account.custom_attributes['subscription_status']
  json.limits account.limits
  json.marketing_attribution account.internal_attributes['marketing_attribution']
end
