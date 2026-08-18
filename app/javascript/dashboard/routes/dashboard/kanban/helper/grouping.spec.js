import { contactKeyOf, groupRecordsByContact } from './grouping';

const record = (id, overrides = {}) => ({
  id,
  status: 'open',
  created_at: 0,
  last_activity_at: 0,
  custom_attributes: {},
  meta: { sender: {} },
  ...overrides,
});

describe('contactKeyOf', () => {
  it('prefere o id do contato', () => {
    expect(
      contactKeyOf(
        record(1, { meta: { sender: { id: 42, phone_number: '+55 11 9' } } })
      )
    ).toBe('contact:42');
  });

  it('cai no telefone normalizado quando não há id', () => {
    expect(
      contactKeyOf(
        record(1, { meta: { sender: { phone_number: '+55 (11) 99129-0550' } } })
      )
    ).toBe('phone:5511991290550');
  });

  it('isola registros sem contato/telefone (não agrupa)', () => {
    expect(contactKeyOf(record(7, { meta: { sender: {} } }))).toBe('conv:7');
  });
});

describe('groupRecordsByContact', () => {
  it('colapsa conversas do mesmo número em um card só', () => {
    const records = [
      record(1, { meta: { sender: { id: 9 } }, last_activity_at: 100 }),
      record(2, { meta: { sender: { id: 9 } }, last_activity_at: 300 }),
      record(3, { meta: { sender: { id: 9 } }, last_activity_at: 200 }),
    ];
    const grouped = groupRecordsByContact(records);
    expect(grouped).toHaveLength(1);
    expect(grouped[0].id).toBe(2); // mais recente vira o card primário
    expect(grouped[0].groupCount).toBe(3);
    expect(grouped[0].groupHistory.map(h => h.id)).toEqual([3, 1]); // recente → antigo
  });

  it('mantém números distintos como cards separados', () => {
    const grouped = groupRecordsByContact([
      record(1, { meta: { sender: { id: 9 } } }),
      record(2, { meta: { sender: { id: 10 } } }),
    ]);
    expect(grouped).toHaveLength(2);
    expect(grouped.every(g => g.groupCount === 1)).toBe(true);
    expect(grouped.every(g => g.groupHistory.length === 0)).toBe(true);
  });

  it('leva stage e outcome para as entradas de histórico', () => {
    const grouped = groupRecordsByContact([
      record(1, {
        meta: { sender: { id: 9 } },
        last_activity_at: 300,
        custom_attributes: { sdr_stage: 'primeiro_contato' },
      }),
      record(2, {
        meta: { sender: { id: 9 } },
        last_activity_at: 100,
        custom_attributes: {
          sdr_stage: 'lead_identificado',
          sdr_outcome: 'lost',
        },
      }),
    ]);
    expect(grouped[0].id).toBe(1);
    expect(grouped[0].groupHistory[0]).toMatchObject({
      id: 2,
      stage: 'lead_identificado',
      outcome: 'lost',
      at: 100,
    });
  });
});
