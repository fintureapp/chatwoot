import { mount, flushPromises } from '@vue/test-utils';
import { computed } from 'vue';
import SidebarNotificationPopover from '../SidebarNotificationPopover.vue';

const dispatch = vi.fn(() => Promise.resolve());
const push = vi.fn();
const apiGet = vi.fn();

const getterValues = {
  getCurrentAccountId: 1,
  'notifications/getUnreadCount': 2,
  'notifications/getMeta': { unreadCount: 2, count: 3 },
  'notifications/getNotifications': [],
  'inboxes/getInboxById': () => ({ id: 4, name: 'WhatsApp' }),
};

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => computed(() => getterValues[key]),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
}));

vi.mock('dashboard/api/notifications', () => ({
  default: { get: (...args) => apiGet(...args) },
}));

const nowInSeconds = Math.floor(Date.now() / 1000);
const notification = (id, overrides = {}) => ({
  id,
  notification_type: 'team_assignment',
  primary_actor_id: 10 + id,
  primary_actor_type: 'Conversation',
  primary_actor: { id: 10 + id, inbox_id: 4, meta: { sender: { name: 'A' } } },
  push_message_body: 'A: hello',
  created_at: nowInSeconds - id * 60,
  last_activity_at: nowInSeconds - id * 60,
  read_at: null,
  ...overrides,
});

const PopoverStub = {
  props: ['align', 'showContentBorder'],
  emits: ['show', 'hide'],
  template:
    '<div><slot :is-open="true" /><slot name="content" :hide="() => {}" /></div>',
};

const mountPopover = () =>
  mount(SidebarNotificationPopover, {
    global: {
      stubs: {
        Popover: PopoverStub,
        InboxCard: { props: ['inboxItem'], template: '<div class="card" />' },
        Spinner: true,
        Icon: true,
        CustomSnoozeModal: true,
        teleport: true,
      },
    },
  });

describe('SidebarNotificationPopover', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiGet.mockResolvedValue({
      data: {
        data: {
          payload: [
            notification(1),
            notification(2, { read_at: nowInSeconds - 30 }),
            notification(3, {
              read_at: nowInSeconds - 30,
              created_at: nowInSeconds - 10 * 24 * 60 * 60,
            }),
          ],
        },
      },
    });
  });

  it('renders the unread badge on the bell', () => {
    const wrapper = mountPopover();
    expect(wrapper.find('button[aria-label]').text()).toContain('2');
  });

  it('splits notifications into unread and last-7-days history', async () => {
    const wrapper = mountPopover();
    wrapper.vm.reload();
    await flushPromises();

    expect(apiGet).toHaveBeenCalledWith(
      expect.objectContaining({ page: 1, status: 'snoozed', type: 'read' })
    );
    // notification 3 is older than 7 days and must be dropped
    expect(wrapper.findAll('.card')).toHaveLength(2);
    expect(wrapper.text()).toContain('Não lidas');
    expect(wrapper.text()).toContain('Últimos 7 dias');
  });

  it('marks all notifications as read through the store', async () => {
    const wrapper = mountPopover();
    wrapper.vm.reload();
    await flushPromises();

    await wrapper.find('[data-testid="mark-all-read"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('notifications/readAll');
    expect(wrapper.vm.items.every(item => item.readAt)).toBe(true);
  });

  it('navigates to the full notifications page from "view all"', async () => {
    const wrapper = mountPopover();
    await wrapper.find('[data-testid="view-all"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'inbox_view',
      params: { accountId: 1 },
    });
  });
});
