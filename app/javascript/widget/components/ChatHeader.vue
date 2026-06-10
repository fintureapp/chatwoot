<script setup>
import { toRef } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import HeaderActions from './HeaderActions.vue';
import AvailabilityContainer from 'widget/components/Availability/AvailabilityContainer.vue';
import { useAvailability } from 'widget/composables/useAvailability';
import { useArticleView } from 'widget/composables/useArticleView';

const props = defineProps({
  avatarUrl: { type: String, default: '' },
  title: { type: String, default: '' },
  showPopoutButton: { type: Boolean, default: false },
  showBackButton: { type: Boolean, default: false },
  availableAgents: { type: Array, default: () => [] },
});

const availableAgents = toRef(props, 'availableAgents');

const router = useRouter();
const { t } = useI18n();
const { isOnline } = useAvailability(availableAgents);
const { isArticleView, isWidgetExpanded, toggleWidgetExpanded } =
  useArticleView();

const onBackButtonClick = () => {
  router.replace({ name: 'home' });
};
</script>

<template>
  <header class="flex justify-between w-full p-5 bg-n-background gap-2">
    <div class="flex items-center">
      <button
        v-if="showBackButton"
        class="px-2 ltr:-ml-3 rtl:-mr-3"
        @click="onBackButtonClick"
      >
        <FluentIcon icon="chevron-left" size="24" class="text-n-slate-12" />
      </button>
      <img
        v-if="avatarUrl"
        class="w-8 h-8 ltr:mr-3 rtl:ml-3 rounded-full"
        :src="avatarUrl"
        alt="avatar"
      />
      <div class="flex flex-col gap-1">
        <div
          class="flex items-center text-base font-medium leading-4 text-n-slate-12"
        >
          <span v-dompurify-html="title" class="ltr:mr-1 rtl:ml-1" />
          <div
            :class="`h-2 w-2 rounded-full
              ${isOnline ? 'bg-n-teal-10' : 'hidden'}`"
          />
        </div>
        <AvailabilityContainer
          :agents="availableAgents"
          :show-header="false"
          :show-avatars="false"
          text-classes="text-xs leading-3"
        />
      </div>
    </div>
    <div class="flex items-center gap-3">
      <button
        v-if="isArticleView"
        class="button transparent compact"
        :title="
          isWidgetExpanded
            ? t('PORTAL.COLLAPSE_ARTICLE')
            : t('PORTAL.EXPAND_ARTICLE')
        "
        @click="toggleWidgetExpanded"
      >
        <span
          class="size-4 text-n-slate-12"
          :class="
            isWidgetExpanded ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'
          "
        />
      </button>
      <HeaderActions :show-popout-button="showPopoutButton" />
    </div>
  </header>
</template>
