class Api::V1::Accounts::Microsoft::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include MicrosoftConcern

  def create
    return render json: { success: false, error: 'invalid_mailbox' }, status: :unprocessable_entity if requested_mailbox_invalid?

    redirect_url = microsoft_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/microsoft/callback",
        scope: scope,
        state: state,
        # Let the admin pick the delegate identity instead of silently reusing their own session
        prompt: requested_mailbox.present? ? 'select_account' : nil
      }.compact
    )
    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  # `email` names the mailbox to connect: a shared mailbox the signing-in identity was delegated,
  # or the inbox being reauthorized. Without it the signed-in identity's own mailbox is connected.
  def state
    return super if requested_mailbox.blank?

    Microsoft::OauthState.wrap(super, requested_mailbox)
  end

  def requested_mailbox
    @requested_mailbox ||= params[:email].to_s.strip.downcase.presence
  end

  def requested_mailbox_invalid?
    requested_mailbox.present? && !requested_mailbox.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
