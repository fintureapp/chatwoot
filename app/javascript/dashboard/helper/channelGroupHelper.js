import { INBOX_TYPES } from './inbox';

/**
 * Channel groups used by the conversations list channel toggle
 * (WhatsApp / Email / All).
 */
export const CHANNEL_GROUPS = {
  WHATSAPP: 'whatsapp',
  EMAIL: 'email',
};

/**
 * Resolves which channel group an inbox belongs to.
 *
 * A manual classification stored on the account
 * (`custom_attributes.channel_groups`) always wins — this is how API/other
 * inboxes that actually relay WhatsApp or email get grouped. When there is no
 * manual override we fall back to the inbox's native channel type.
 *
 * @param {Object} inbox - Inbox record (snake_case or camelCase).
 * @param {Object} [channelGroupsMap={}] - Map of inbox id -> group.
 * @returns {('whatsapp'|'email'|null)} The resolved group, or null when unknown.
 */
export const resolveInboxChannelGroup = (inbox, channelGroupsMap = {}) => {
  if (!inbox) return null;

  const manual =
    channelGroupsMap[inbox.id] ?? channelGroupsMap[String(inbox.id)];
  if (manual === CHANNEL_GROUPS.WHATSAPP || manual === CHANNEL_GROUPS.EMAIL) {
    return manual;
  }

  const channelType = inbox.channel_type || inbox.channelType;
  if (channelType === INBOX_TYPES.WHATSAPP) return CHANNEL_GROUPS.WHATSAPP;
  if (channelType === INBOX_TYPES.EMAIL) return CHANNEL_GROUPS.EMAIL;

  return null;
};

/**
 * Returns the ids of the inboxes that belong to a given channel group.
 *
 * @param {Array} inboxes - Inbox records.
 * @param {Object} channelGroupsMap - Map of inbox id -> group.
 * @param {('whatsapp'|'email'|null)} group - Target group.
 * @returns {(number[]|undefined)} Matching inbox ids, or undefined when no
 *   group is selected (i.e. "All").
 */
export const getInboxIdsForChannelGroup = (
  inboxes,
  channelGroupsMap,
  group
) => {
  if (!group) return undefined;

  return (inboxes || [])
    .filter(
      inbox => resolveInboxChannelGroup(inbox, channelGroupsMap) === group
    )
    .map(inbox => inbox.id);
};
