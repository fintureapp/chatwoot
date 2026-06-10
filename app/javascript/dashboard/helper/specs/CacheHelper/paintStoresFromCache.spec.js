import paintStoresFromCache from '../../CacheHelper/paintStoresFromCache';
import { DataManager } from '../../CacheHelper/DataManager';

describe('paintStoresFromCache', () => {
  const accountId = 'paint-test-account';
  const originalAxios = window.axios;
  let axiosMock;
  let dm;
  let storeMock;

  beforeEach(async () => {
    axiosMock = {
      get: vi.fn(),
    };
    window.axios = axiosMock;

    storeMock = {
      commit: vi.fn(),
      dispatch: vi.fn(),
    };

    dm = new DataManager(accountId);
    await dm.initDb();
  });

  afterEach(async () => {
    const tx = dm.db.transaction(
      [...dm.modelsToSync, 'cache-keys'],
      'readwrite'
    );
    [...dm.modelsToSync, 'cache-keys'].forEach(name => {
      tx.objectStore(name).clear();
    });
    await tx.done;
    window.axios = originalAxios;
  });

  it('does nothing when IDB is empty (first ever load)', async () => {
    await paintStoresFromCache(storeMock, accountId);

    expect(storeMock.commit).not.toHaveBeenCalled();
    expect(storeMock.dispatch).not.toHaveBeenCalled();
  });

  it('seeds Vuex from IDB without any network interaction', async () => {
    await dm.push({
      modelName: 'inbox',
      data: [{ id: 1, name: 'Support' }],
    });
    await dm.push({
      modelName: 'label',
      data: [{ id: 9, title: 'Bug' }],
    });

    await paintStoresFromCache(storeMock, accountId);

    expect(storeMock.commit).toHaveBeenCalledWith('inboxes/SET_INBOXES', [
      { id: 1, name: 'Support' },
    ]);
    expect(storeMock.commit).toHaveBeenCalledWith('labels/SET_LABELS', [
      { id: 9, title: 'Bug' },
    ]);
    expect(axiosMock.get).not.toHaveBeenCalled();
    expect(storeMock.dispatch).not.toHaveBeenCalled();
  });

  it('seeds teams via SET_TEAMS', async () => {
    await dm.push({
      modelName: 'team',
      data: [{ id: 1, name: 'Sales' }],
    });

    await paintStoresFromCache(storeMock, accountId);

    expect(storeMock.commit).toHaveBeenCalledWith('teams/SET_TEAMS', [
      { id: 1, name: 'Sales' },
    ]);
  });
});
