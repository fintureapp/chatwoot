<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { emitter } from 'shared/helpers/mitt';
import { ON_ARTICLE_VIEW_RESIZING } from 'widget/constants/widgetBusEvents';
import IframeLoader from 'shared/components/IframeLoader.vue';

const route = useRoute();

// Masks the article while the widget resizes (see App.vue#setArticleView) so the
// iframe's text reflow happens off-screen instead of shifting in front of the user.
const isResizing = ref(false);
const setResizing = value => {
  isResizing.value = value;
};

onMounted(() => emitter.on(ON_ARTICLE_VIEW_RESIZING, setResizing));
onBeforeUnmount(() => emitter.off(ON_ARTICLE_VIEW_RESIZING, setResizing));
</script>

<template>
  <div class="bg-white dark:bg-slate-900 h-full relative">
    <!--
      Key by fullPath (not just the link) so the iframe remounts on every
      navigation here, including re-opening the same article via the SDK after
      the iframe was browsed to another help-center page. See App.vue#openArticle.
    -->
    <IframeLoader :key="route.fullPath" :url="route.query.link" />
    <!--
      Cover the article instantly while the widget resizes, then fade it out once
      the size transition settles. The asymmetric class (no transition on the way
      in, transition on the way out) keeps the cover from revealing the reflow.
    -->
    <div
      class="absolute inset-0 bg-white dark:bg-slate-900 pointer-events-none"
      :class="
        isResizing ? 'opacity-100' : 'opacity-0 transition-opacity duration-100'
      "
    />
  </div>
</template>
