<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert, useTrack } from 'dashboard/composables';
import { PORTALS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import {
  buildPortalArticleURL,
  ARTICLE_STATUSES,
} from 'dashboard/helper/portalHelper';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import { buildDiffBlocks } from 'dashboard/helper/articleDiffHelper';

import ArticleEditor from 'dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const { articleSlug, portalSlug } = route.params;

const articleById = useMapGetter('articles/articleById');

const article = computed(() => articleById.value(articleSlug));

const portalBySlug = useMapGetter('portals/portalBySlug');

const portal = computed(() => portalBySlug.value(portalSlug));

const isUpdating = ref(false);
const isSaved = ref(false);

const articleLink = computed(() => {
  const { slug: categorySlug, locale: categoryLocale } = article.value.category;
  const { slug: articleSlugValue } = article.value;
  const portalCustomDomain = portal.value?.custom_domain;
  return buildPortalArticleURL(
    portalSlug,
    categorySlug,
    categoryLocale,
    articleSlugValue,
    portalCustomDomain
  );
});

// Two versions match when the diff view would show nothing between them — this
// ignores whitespace-only differences the same way the diff does.
const unchanged = (live, next) =>
  buildDiffBlocks(live, next).every(block => block.type === 'equal');

// On a published article, title/content edits stage into draft_* columns (kept
// off the live site). Anywhere else they save straight to the live record — and
// we drop any leftover draft (e.g. left behind when the card/bulk menu moved a
// published article to draft) so a later publish can't resurrect stale content.
const stageDraftFields = values => {
  if (article.value?.status !== ARTICLE_STATUSES.PUBLISHED) {
    const hasStaleDraft =
      article.value?.draftTitle != null || article.value?.draftContent != null;
    return hasStaleDraft
      ? { ...values, draft_title: null, draft_content: null }
      : values;
  }

  const staged = { ...values };
  ['title', 'content'].forEach(field => {
    if (field in staged) {
      staged[`draft_${field}`] = staged[field];
      delete staged[field];
    }
  });

  // Clear the draft when it has no visible difference from the live version, so
  // a revert — or a whitespace-only edit the diff ignores (e.g. an extra blank
  // line) — doesn't leave a "pending changes" badge with nothing to compare.
  const liveTitle = article.value.title ?? '';
  const liveContent = article.value.content ?? '';
  const nextTitle = staged.draft_title ?? article.value.draftTitle ?? liveTitle;
  const nextContent =
    staged.draft_content ?? article.value.draftContent ?? liveContent;
  if (unchanged(liveTitle, nextTitle) && unchanged(liveContent, nextContent)) {
    staged.draft_title = null;
    staged.draft_content = null;
  }

  return staged;
};

const saveArticle = async ({ ...values }) => {
  isUpdating.value = true;
  try {
    await store.dispatch('articles/update', {
      portalSlug,
      articleId: articleSlug,
      ...stageDraftFields(values),
    });
    isSaved.value = true;
  } catch (error) {
    const errorMessage =
      error?.message || t('HELP_CENTER.EDIT_ARTICLE_PAGE.API.ERROR');
    useAlert(errorMessage);
  } finally {
    setTimeout(() => {
      isUpdating.value = false;
      isSaved.value = true;
    }, 1500);
  }
};

const isCategoryArticles = computed(() => {
  return (
    route.name === 'portals_categories_articles_index' ||
    route.name === 'portals_categories_articles_edit' ||
    route.name === 'portals_categories_index'
  );
});

const goBackToArticles = () => {
  const { tab, categorySlug, locale } = route.params;
  if (isCategoryArticles.value) {
    router.push({
      name: 'portals_categories_articles_index',
      params: { categorySlug, locale },
    });
  } else {
    router.push({
      name: 'portals_articles_index',
      params: { tab, categorySlug, locale },
    });
  }
};

const fetchArticleDetails = () => {
  store.dispatch('articles/show', {
    id: articleSlug,
    portalSlug,
  });
};

const previewArticle = () => {
  window.open(articleLink.value, '_blank');
  useTrack(PORTALS_EVENTS.PREVIEW_ARTICLE, {
    status: article.value?.status,
  });
};

onMounted(fetchArticleDetails);
</script>

<template>
  <ArticleEditor
    :article="article"
    :is-updating="isUpdating"
    :is-saved="isSaved"
    @save-article="saveArticle"
    @preview-article="previewArticle"
    @go-back="goBackToArticles"
  />
</template>
