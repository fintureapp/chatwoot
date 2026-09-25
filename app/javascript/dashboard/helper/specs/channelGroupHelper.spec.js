import {
  CHANNEL_GROUPS,
  resolveInboxChannelGroup,
  getInboxIdsForChannelGroup,
} from '../channelGroupHelper';

const whatsappInbox = { id: 1, channel_type: 'Channel::Whatsapp' };
const emailInbox = { id: 2, channel_type: 'Channel::Email' };
const apiInbox = { id: 3, channel_type: 'Channel::Api' };
const webInbox = { id: 4, channel_type: 'Channel::WebWidget' };

describe('#resolveInboxChannelGroup', () => {
  it('returns null for a missing inbox', () => {
    expect(resolveInboxChannelGroup(null)).toBeNull();
  });

  it('resolves native WhatsApp channels automatically', () => {
    expect(resolveInboxChannelGroup(whatsappInbox)).toBe(
      CHANNEL_GROUPS.WHATSAPP
    );
  });

  it('resolves native Email channels automatically', () => {
    expect(resolveInboxChannelGroup(emailInbox)).toBe(CHANNEL_GROUPS.EMAIL);
  });

  it('returns null for channels with no native group and no override', () => {
    expect(resolveInboxChannelGroup(apiInbox)).toBeNull();
    expect(resolveInboxChannelGroup(webInbox)).toBeNull();
  });

  it('lets a manual classification win over the native type', () => {
    // An API inbox that actually relays WhatsApp, classified by the admin.
    expect(
      resolveInboxChannelGroup(apiInbox, { 3: CHANNEL_GROUPS.WHATSAPP })
    ).toBe(CHANNEL_GROUPS.WHATSAPP);
  });

  it('accepts string keys in the classification map', () => {
    expect(
      resolveInboxChannelGroup(apiInbox, { 3: CHANNEL_GROUPS.EMAIL })
    ).toBe(CHANNEL_GROUPS.EMAIL);
  });

  it('ignores invalid values in the classification map', () => {
    expect(resolveInboxChannelGroup(whatsappInbox, { 1: 'nonsense' })).toBe(
      CHANNEL_GROUPS.WHATSAPP
    );
  });

  it('supports camelCase inbox records', () => {
    expect(
      resolveInboxChannelGroup({ id: 9, channelType: 'Channel::Email' })
    ).toBe(CHANNEL_GROUPS.EMAIL);
  });
});

describe('#getInboxIdsForChannelGroup', () => {
  const inboxes = [whatsappInbox, emailInbox, apiInbox, webInbox];

  it('returns undefined when no group is selected (All)', () => {
    expect(getInboxIdsForChannelGroup(inboxes, {}, null)).toBeUndefined();
  });

  it('returns native WhatsApp inbox ids', () => {
    expect(
      getInboxIdsForChannelGroup(inboxes, {}, CHANNEL_GROUPS.WHATSAPP)
    ).toEqual([1]);
  });

  it('includes manually classified inboxes in the group', () => {
    const map = { 3: CHANNEL_GROUPS.WHATSAPP };
    expect(
      getInboxIdsForChannelGroup(inboxes, map, CHANNEL_GROUPS.WHATSAPP)
    ).toEqual([1, 3]);
  });

  it('returns an empty array when a group has no inboxes', () => {
    expect(
      getInboxIdsForChannelGroup([apiInbox, webInbox], {}, CHANNEL_GROUPS.EMAIL)
    ).toEqual([]);
  });
});
