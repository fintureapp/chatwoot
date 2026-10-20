import {
  buildQuickFilterConditions,
  countQuickFilters,
  emptyQuickFilters,
  inboxesForTipos,
  stageOptionsFor,
  stageValuesFor,
} from '../quickFilterHelper';

const stagesByInbox = {
  1: [
    { slug: 'lead_identificado', name: 'Lead Identificado' },
    { slug: 'proposta_enviada', name: 'Proposta Enviada' },
  ],
  2: [
    { slug: 'triagem', name: 'Triagem' },
    { slug: 'proposta_enviada', name: 'Proposta Enviada' },
  ],
};

describe('quickFilterHelper', () => {
  it('counts only the filters with values', () => {
    expect(countQuickFilters(emptyQuickFilters())).toBe(0);
    expect(
      countQuickFilters({
        ...emptyQuickFilters(),
        status: ['open'],
        label: ['x'],
      })
    ).toBe(2);
  });

  it('merges the stages of the selected inboxes without duplicates', () => {
    expect(stageOptionsFor([1, 2], stagesByInbox).map(s => s.slug)).toEqual([
      'lead_identificado',
      'proposta_enviada',
      'triagem',
    ]);
    expect(stageOptionsFor([], stagesByInbox)).toEqual([]);
  });

  it('adds the empty stage when the first column is selected', () => {
    expect(stageValuesFor(['triagem'], [2], stagesByInbox)).toEqual([
      'triagem',
      '',
    ]);
    expect(stageValuesFor(['proposta_enviada'], [1, 2], stagesByInbox)).toEqual(
      ['proposta_enviada']
    );
  });

  it('builds one equal_to condition per filled filter', () => {
    const conditions = buildQuickFilterConditions(
      {
        ...emptyQuickFilters(),
        status: ['open'],
        inbox: [1],
        stage: ['lead_identificado'],
        team: [7],
        agent: [9],
      },
      { stagesByInbox }
    );
    expect(conditions.map(c => [c.attribute_key, c.values])).toEqual([
      ['inbox_id', [1]],
      ['sdr_stage', ['lead_identificado', '']],
      ['status', ['open']],
      ['team_id', [7]],
      ['assignee_id', [9]],
    ]);
    expect(conditions[0]).toMatchObject({
      filter_operator: 'equal_to',
      query_operator: 'and',
    });
  });

  it('uses the inboxes of the chosen type when no inbox is chosen', () => {
    const conditions = buildQuickFilterConditions(
      {
        ...emptyQuickFilters(),
        tipo: ['whatsapp'],
        priority: ['high'],
        stage: ['triagem'],
      },
      { stagesByInbox, tipoInboxIds: [3, 4] }
    );
    expect(conditions.map(c => [c.attribute_key, c.values])).toEqual([
      ['inbox_id', [3, 4]],
      ['priority', ['high']],
    ]);
  });

  it('returns nothing for a type without inboxes', () => {
    const conditions = buildQuickFilterConditions(
      { ...emptyQuickFilters(), tipo: ['email'] },
      { tipoInboxIds: [] }
    );
    expect(conditions.map(c => [c.attribute_key, c.values])).toEqual([
      ['inbox_id', [0]],
    ]);
  });

  it('groups inboxes by channel type, unclassified ones as other', () => {
    const inboxes = [
      { id: 1, channel_type: 'Channel::Whatsapp' },
      { id: 2, channel_type: 'Channel::Email' },
      { id: 3, channel_type: 'Channel::Api' },
      { id: 4, channel_type: 'Channel::Api' },
    ];
    const groups = { 4: 'whatsapp' };
    const ids = tipos => inboxesForTipos(tipos, inboxes, groups).map(i => i.id);
    expect(ids(['whatsapp'])).toEqual([1, 4]);
    expect(ids(['other'])).toEqual([3]);
    expect(ids([])).toEqual([1, 2, 3, 4]);
  });
});
