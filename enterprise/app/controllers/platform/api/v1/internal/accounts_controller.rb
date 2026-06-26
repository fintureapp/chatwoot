# frozen_string_literal: true

class Platform::Api::V1::Internal::AccountsController < ActionController::API
  include RequestExceptionHandler

  CONFIG_KEY = 'CHATWOOT_CLOUD_SIGNALS_API_TOKEN'
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 1000

  before_action :authenticate_internal_token!

  def index
    return render_not_found unless ChatwootApp.chatwoot_cloud?

    @accounts = filtered_accounts.limit(limit)
  end

  private

  def authenticate_internal_token!
    return if internal_token.present? && secure_token_match?(request_token, internal_token)

    render json: { error: 'Invalid access_token' }, status: :unauthorized
  end

  def render_not_found
    render json: { error: 'Not found' }, status: :not_found
  end

  def request_token
    bearer_token || request.headers[:api_access_token] || request.headers[:HTTP_API_ACCESS_TOKEN]
  end

  def bearer_token
    request.authorization&.split&.then { |scheme, token| token if scheme&.casecmp('Bearer')&.zero? }
  end

  def internal_token
    @internal_token ||= GlobalConfigService.load(CONFIG_KEY, nil)
  end

  def secure_token_match?(token, configured_token)
    return false if token.blank? || configured_token.blank? || token.bytesize != configured_token.bytesize

    ActiveSupport::SecurityUtils.secure_compare(token, configured_token)
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
