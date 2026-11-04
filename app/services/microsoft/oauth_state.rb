# Carries the mailbox the admin asked to connect through the Microsoft OAuth round-trip.
#
# The plain state is the account sgid (see OauthAuthorizationController#state). When a target
# mailbox is given (a shared mailbox, or the inbox being reauthorized), the sgid and the mailbox
# are signed together so the callback can trust both. A state without a mailbox stays the plain
# sgid, so the default flow is unchanged.
module Microsoft::OauthState
  PURPOSE = :microsoft_oauth_mailbox

  module_function

  def wrap(account_state, mailbox)
    verifier.generate({ 'state' => account_state, 'mailbox' => mailbox }, purpose: PURPOSE, expires_in: 15.minutes)
  end

  # Returns [account_state, mailbox]; mailbox is nil for a plain (unwrapped) state.
  def unwrap(raw_state)
    payload = verifier.verified(raw_state.to_s, purpose: PURPOSE)
    return [raw_state, nil] unless payload.is_a?(Hash)

    [payload['state'], payload['mailbox']]
  rescue StandardError
    [raw_state, nil]
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
