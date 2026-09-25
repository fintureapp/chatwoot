import { DashboardAudioNotificationHelper } from '../DashboardAudioNotificationHelper';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

describe('DashboardAudioNotificationHelper#onAssignmentNotification', () => {
  let helper;

  beforeEach(() => {
    vi.clearAllMocks();
    const store = {
      getters: {
        getMineChats: vi.fn(),
        getSelectedChat: null,
        getCurrentAccountId: 1,
        getConversationById: vi.fn(),
      },
    };
    helper = new DashboardAudioNotificationHelper(store);
    helper.playAudioAlert = vi.fn();
    helper.intializeAudio = vi.fn();
    helper.notificationConfig.audioAlertType = ['none'];
    helper.audioConfig.audio = {};
  });

  it('plays the tone and shows a toast for a conversation assignment', () => {
    helper.notificationConfig.audioAlertType = ['mine'];

    helper.onAssignmentNotification({
      notification_type: 'conversation_assignment',
      push_message_title: 'A conversation (#1) has been assigned to you',
    });

    expect(useAlert).toHaveBeenCalledWith(
      'A conversation (#1) has been assigned to you'
    );
    expect(helper.playAudioAlert).toHaveBeenCalled();
  });

  it('plays the tone and shows a toast for a team assignment', () => {
    helper.notificationConfig.audioAlertType = ['mine'];

    helper.onAssignmentNotification({
      notification_type: 'team_assignment',
      push_message_title: 'A conversation (#1) has been assigned to your team',
    });

    expect(useAlert).toHaveBeenCalled();
    expect(helper.playAudioAlert).toHaveBeenCalled();
  });

  it('ignores non-assignment notification types', () => {
    helper.notificationConfig.audioAlertType = ['mine'];

    helper.onAssignmentNotification({
      notification_type: 'conversation_mention',
      push_message_title: 'You have been mentioned',
    });

    expect(useAlert).not.toHaveBeenCalled();
    expect(helper.playAudioAlert).not.toHaveBeenCalled();
  });

  it('shows the toast but skips the sound when audio alerts are muted', () => {
    helper.notificationConfig.audioAlertType = ['none'];

    helper.onAssignmentNotification({
      notification_type: 'conversation_assignment',
      push_message_title: 'A conversation (#1) has been assigned to you',
    });

    expect(useAlert).toHaveBeenCalled();
    expect(helper.playAudioAlert).not.toHaveBeenCalled();
  });
});
