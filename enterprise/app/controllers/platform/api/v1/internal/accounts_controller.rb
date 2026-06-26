# frozen_string_literal: true

class Platform::Api::V1::Internal::AccountsController < ActionController::API
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 1000

  before_action :ensure_chatwoot_cloud
  before_action :authenticate_internal_token!

  def index
    @accounts = filtered_accounts.limit(limit)
  end

  private

  def ensure_chatwoot_cloud
    render json: { error: 'Not found' }, status: :not_found unless ChatwootApp.chatwoot_cloud?
  end

  def authenticate_internal_token!
    token = request.headers[:api_access_token] || request.headers[:HTTP_API_ACCESS_TOKEN]
    config_token = GlobalConfigService.load('CHATWOOT_CLOUD_SIGNALS_API_TOKEN', nil)
    return if token.present? && config_token.present? && ActiveSupport::SecurityUtils.secure_compare(token, config_token)

    render json: { error: 'Invalid access_token' }, status: :unauthorized
  end

  def filtered_accounts
    scope = Account.order(:created_at, :id)
    scope = scope.where('created_at >= ?', Time.zone.at(params[:since].to_i)) if params[:since].present?
    scope = scope.where('created_at <= ?', Time.zone.at(params[:until].to_i)) if params[:until].present?
    scope
  end

  def limit
    params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end
end
