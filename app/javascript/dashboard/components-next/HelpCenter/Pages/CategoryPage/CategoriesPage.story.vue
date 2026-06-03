<script setup>
import CategoriesPage from './CategoriesPage.vue';

const categories = [
  {
    id: 1,
    name: 'Getting started',
    icon: '🚀',
    slug: 'getting-started',
    description:
      'Learn how to use Chatwoot effectively and make the most of its features to enhance customer support and engagement.',
    meta: { articles_count: 12 },
  },
  {
    id: 2,
    name: 'Marketing',
    icon: '⚡️',
    slug: 'marketing',
    description:
      'Learn how to use Chatwoot effectively and make the most of its features to enhance customer support.',
    meta: { articles_count: 4 },
  },
  {
    id: 3,
    name: 'Development',
    icon: '🛠️',
    slug: 'development',
    description: '',
    meta: { articles_count: 5 },
  },
  {
    id: 4,
    name: 'Roadmap',
    icon: '🛣️',
    slug: 'roadmap',
    description:
      'Learn how to use Chatwoot effectively and make the most of its features to enhance customer support and engagement.',
    meta: { articles_count: 3 },
  },
  {
    id: 5,
    name: 'Finance',
    icon: '💰',
    slug: 'finance',
    description:
      'Learn how to use Chatwoot effectively and make the most of its features to enhance customer support and engagement.',
    meta: { articles_count: 2 },
  },
];

const allowedLocales = [{ code: 'en', name: 'English' }];
</script>

<template>
  <Story title="Pages/HelpCenter/CategoryPage" :layout="{ type: 'single' }">
    <Variant title="All Categories">
      <div class="w-full min-h-screen bg-n-background">
        <CategoriesPage
          :categories="categories"
          :allowed-locales="allowedLocales"
        />
      </div>
    </Variant>
  </Story>
</template>
