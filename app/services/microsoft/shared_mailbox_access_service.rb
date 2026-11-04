require 'net/imap'

# Checks that a freshly issued token can open a shared mailbox over IMAP before the inbox is
# connected. Exchange only accepts `user=<shared mailbox>` in XOAUTH2 when the signed-in identity
# has Full Access to it, so a failure here means the delegation is missing (or not propagated yet)
# and nothing would ever be fetched. The mailbox is opened read-only (EXAMINE).
class Microsoft::SharedMailboxAccessService
  IMAP_ADDRESS = 'outlook.office365.com'.freeze
  IMAP_PORT = 993

  pattr_initialize [:mailbox!, :access_token!]

  def accessible?
    imap = Net::IMAP.new(IMAP_ADDRESS, port: IMAP_PORT, ssl: true, open_timeout: 15)
    Imap::Authentication.authenticate!(imap, 'XOAUTH2', mailbox, access_token)
    imap.examine('INBOX')
    true
  rescue Net::IMAP::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError, Timeout::Error => e
    Rails.logger.warn("[MICROSOFT_SHARED_MAILBOX] #{mailbox} is not accessible: #{e.class} #{e.message}")
    false
  ensure
    disconnect(imap)
  end

  private

  def disconnect(imap)
    return if imap.nil? || imap.disconnected?

    imap.logout
    imap.disconnect
  rescue StandardError
    nil
  end
end
