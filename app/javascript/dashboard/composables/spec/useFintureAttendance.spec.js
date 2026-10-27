import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import { useFintureAttendance } from '../useFintureAttendance';
import FintureCrmApi from 'dashboard/api/fintureCrm';
import { useAlert } from 'dashboard/composables';

const dispatch = vi.fn(() => Promise.resolve());

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/fintureCrm', () => ({
  default: {
    takeOverConversation: vi.fn(),
    returnConversationToAi: vi.fn(),
  },
}));

const conversationWith = attendance =>
  ref({ id: 7, meta: {}, finture_attendance: attendance });

describe('useFintureAttendance', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fica oculto em caixa sem IA', () => {
    const { isEnabled, isAi } = useFintureAttendance(
      conversationWith({ mode: 'ia', revision: 0, ai_enabled: false })
    );
    expect(isEnabled.value).toBe(false);
    expect(isAi.value).toBe(false);
  });

  it('assume com a revisão exibida e só confirma após o servidor', async () => {
    FintureCrmApi.takeOverConversation.mockResolvedValue({ data: {} });
    const { isAi, takeOver } = useFintureAttendance(
      conversationWith({ mode: 'ia', revision: 3, ai_enabled: true })
    );

    expect(isAi.value).toBe(true);
    await expect(takeOver()).resolves.toBe(true);
    expect(FintureCrmApi.takeOverConversation).toHaveBeenCalledWith(7, {
      expectedRevision: 3,
    });
    expect(dispatch).toHaveBeenCalledWith('getConversation', 7);
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.ATTENDANCE.TAKE_OVER_SUCCESS'
    );
  });

  it('em conflito (409) mostra quem agiu antes e recarrega o estado', async () => {
    FintureCrmApi.takeOverConversation.mockRejectedValue({
      response: { status: 409, data: { error: 'Ana já assumiu às 14:32.' } },
    });
    const { takeOver } = useFintureAttendance(
      conversationWith({ mode: 'ia', revision: 0, ai_enabled: true })
    );

    await expect(takeOver({ silent: true })).resolves.toBe(false);
    expect(useAlert).toHaveBeenCalledWith('Ana já assumiu às 14:32.');
    expect(dispatch).toHaveBeenCalledWith('getConversation', 7);
  });

  it('devolve à IA com motivo e pendências', async () => {
    FintureCrmApi.returnConversationToAi.mockResolvedValue({ data: {} });
    const { returnToAi } = useFintureAttendance(
      conversationWith({ mode: 'humano', revision: 1, ai_enabled: true })
    );

    await expect(
      returnToAi({ reason: 'dúvida simples', pendingNotes: 'enviar boleto' })
    ).resolves.toBe(true);
    expect(FintureCrmApi.returnConversationToAi).toHaveBeenCalledWith(7, {
      expectedRevision: 1,
      reason: 'dúvida simples',
      pendingNotes: 'enviar boleto',
    });
  });
});
