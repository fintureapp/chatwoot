import {
  closedAtOf,
  groupHistoryByContact,
  summaryStateOf,
  SUMMARY_GRACE_SECONDS,
} from './historyGrouping';

const record = (id, contactId, overrides = {}) => ({
  id,
  status: 'resolved',
  created_at: 0,
  last_activity_at: 0,
  custom_attributes: {},
  meta: { sender: { id: contactId, name: `Contato ${contactId}` } },
  ...overrides,
});

describe('closedAtOf', () => {
  it('usa o momento do desfecho quando existe', () => {
    expect(
      closedAtOf(
        record(1, 1, {
          last_activity_at: 50,
          custom_attributes: { sdr_outcome_at: 100 },
        })
      )
    ).toBe(100);
  });

  it('cai na última atividade (demanda resolvida)', () => {
    expect(closedAtOf(record(1, 1, { last_activity_at: 50 }))).toBe(50);
  });
});

describe('groupHistoryByContact', () => {
  it('junta os atendimentos do mesmo contato, mais recente primeiro', () => {
    const closed = (outcome, at) => ({
      custom_attributes: { sdr_outcome: outcome, sdr_outcome_at: at },
    });
    const groups = groupHistoryByContact([
      record(1, 7, closed('lost', 10)),
      record(2, 8, closed('won', 20)),
      record(3, 7, closed('won', 30)),
    ]);

    expect(groups.map(g => g.key)).toEqual(['contact:7', 'contact:8']);
    expect(groups[0].records.map(r => r.id)).toEqual([3, 1]);
    expect(groups[0]).toMatchObject({
      count: 2,
      lastClosedAt: 30,
      wonCount: 1,
      lostCount: 1,
    });
    expect(groups[0].latest.id).toBe(3);
  });

  it('aceita lista vazia ou nula', () => {
    expect(groupHistoryByContact(null)).toEqual([]);
  });
});

describe('summaryStateOf', () => {
  const now = 10_000;

  it('ready quando há resumo', () => {
    expect(summaryStateOf({ resumo: 'x', closedAt: now, now })).toBe('ready');
  });

  it('open quando o atendimento não fechou', () => {
    expect(summaryStateOf({ resumo: '', closedAt: null, now })).toBe('open');
  });

  it('pending logo após fechar e missing depois da janela', () => {
    expect(summaryStateOf({ resumo: '', closedAt: now - 60, now })).toBe(
      'pending'
    );
    expect(
      summaryStateOf({
        resumo: '',
        closedAt: now - SUMMARY_GRACE_SECONDS - 1,
        now,
      })
    ).toBe('missing');
  });
});
