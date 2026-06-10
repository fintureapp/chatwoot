import { ref } from 'vue';
import { LocalStorage } from 'shared/helpers/localStorage';

const EXPANDED_STORAGE_KEY = 'chatwoot:widget:articleViewExpanded';

// Module-level singletons so the header toggle and the resize logic in App.vue
// share a single source of truth.
//
// `isArticleView`   - whether the iframe is currently showing an article page.
// `isWidgetExpanded`- the user's persisted expand/collapse preference. Defaults
//                     to collapsed and only ever applies on article pages.
const isArticleView = ref(false);
const isWidgetExpanded = ref(LocalStorage.get(EXPANDED_STORAGE_KEY) === true);

export function useArticleView() {
  const setArticleView = value => {
    isArticleView.value = value;
  };

  const toggleWidgetExpanded = () => {
    isWidgetExpanded.value = !isWidgetExpanded.value;
    LocalStorage.set(EXPANDED_STORAGE_KEY, isWidgetExpanded.value);
  };

  return {
    isArticleView,
    isWidgetExpanded,
    setArticleView,
    toggleWidgetExpanded,
  };
}
