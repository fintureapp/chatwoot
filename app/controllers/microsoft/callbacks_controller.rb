class Microsoft::CallbacksController < OauthCallbackController
  include MicrosoftConcern

  private

  def oauth_client
    microsoft_client
  end

  def provider_name
    'microsoft'
  end

  def imap_address
    'outlook.office365.com'
  end

  def handle_response
    return redirect_to(shared_mailbox_error_url) if shared_mailbox? && !shared_mailbox_accessible?

    super
  end

  def signed_state
    oauth_state.first
  end

  def oauth_state
    @oauth_state ||= Microsoft::OauthState.unwrap(params[:state])
  end

  # Mailbox chosen on the authorization request (a shared mailbox, or the inbox being reauthorized).
  def requested_mailbox
    oauth_state.last.presence
  end

  # A shared mailbox has no sign-in of its own: a delegate signs in and Exchange lets that identity
  # open the mailbox (Full Access) and send as it (Send As). Asking for any address other than the
  # signed-in identity's own means connecting such a mailbox.
  def shared_mailbox?
    requested_mailbox.present? && signed_in_addresses.exclude?(requested_mailbox.downcase)
  end

  def signed_in_addresses
    users_data.values_at('email', 'preferred_username', 'upn').compact.map(&:downcase)
  end

  def channel_email_address
    shared_mailbox? ? requested_mailbox : super
  end

  # Named after the mailbox (e.g. "Comercial"), not after the delegate who signed in.
  def inbox_name
    shared_mailbox? ? fallback_name : super
  end

  # IMAP XOAUTH2 `user=` names the mailbox to open: the shared mailbox itself when delegated,
  # otherwise the signed-in identity.
  def imap_login_identity
    shared_mailbox? ? requested_mailbox : delegate_login
  end

  # Exchange Online's SMTP AUTH (XOAUTH2) rejects proxy addresses in the SASL `user=` field;
  # it must match the token's UPN. `preferred_username` is the documented v2.0 claim;
  # `upn` is the v1.0 fallback.
  def delegate_login
    users_data['preferred_username'] || users_data['upn'] || users_data['email']
  end

  # SMTP always authenticates as the token owner; sending from a shared mailbox relies on Send As.
  def additional_channel_attributes
    { smtp_login: delegate_login }
  end

  def shared_mailbox_accessible?
    Microsoft::SharedMailboxAccessService.new(mailbox: requested_mailbox, access_token: parsed_body['access_token']).accessible?
  end

  def shared_mailbox_error_url
    app_new_email_inbox_url(account_id: account.id, provider: 'microsoft', error: 'shared_mailbox_access', mailbox: requested_mailbox)
  end
end
