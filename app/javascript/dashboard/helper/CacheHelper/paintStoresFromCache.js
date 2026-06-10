import { DataManager } from './DataManager';
import { cacheableModels } from './cacheableModels';

// Seed Vuex from IndexedDB before the dashboard renders so warm boots paint
// cached config instantly. This is purely local — zero network calls.
//
// Freshness is handled entirely by the account.cache_invalidated event:
// RoomChannel transmits the current cache-key map on every (re)subscribe, and
// the server broadcasts it on every change. dispatchCacheRevalidations diffs
// those keys against IDB and refetches mismatches — the client never pulls
// cache keys itself.
export default async function paintStoresFromCache(store, accountId) {
  let dm;
  try {
    dm = new DataManager(accountId);
    await dm.initDb();
  } catch {
    // IDB unsupported (e.g. Firefox private mode) — silent no-op. Components
    // will fetch from the network normally via the cache-enabled API client.
    return;
  }

  // Stale-while-revalidate paint: commit cached data into Vuex immediately.
  await Promise.all(
    cacheableModels.map(async model => {
      const localData = await dm.get({ modelName: model.name });
      if (localData.length === 0) return;
      store.commit(model.setMutation, localData);
    })
  );
}
