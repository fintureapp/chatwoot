<script setup>
import ArticlesPage from './ArticlesPage.vue';

const articles = [
  {
    title: "How to get an SSL certificate for your Help Center's custom domain",
    status: 'draft',
    updatedAt: '2 days ago',
    author: 'Michael',
    category: '⚡️ Marketing',
    views: 3400,
  },
  {
    title: 'Setting up your first Help Center portal',
    status: '',
    updatedAt: '1 week ago',
    author: 'John',
    category: '🛠️ Development',
    views: 400,
  },
  {
    title: 'Best practices for organizing your Help Center content',
    status: 'archived',
    updatedAt: '3 days ago',
    author: 'Fernando',
    category: '💰 Finance',
    views: 400,
  },
  {
    title: 'Customizing the appearance of your Help Center',
    status: '',
    updatedAt: '5 days ago',
    author: 'Jane',
    category: '💰 Finance',
    views: 400,
  },
  {
    title: 'Best practices for organizing your Help Center content',
    status: 'archived',
    updatedAt: '3 days ago',
    author: 'Fernando',
    category: '💰 Finance',
    views: 400,
  },
  {
    title: 'Customizing the appearance of your Help Center',
    status: '',
    updatedAt: '5 days ago',
    author: 'Jane',
    category: '💰 Finance',
    views: 400,
  },
  {
    title: 'Best practices for organizing your Help Center content',
    status: 'archived',
    updatedAt: '3 days ago',
    author: 'Fernando',
    category: '💰 Finance',
    views: 400,
  },
];

const categories = [
  { id: 1, name: 'Getting started', icon: '🚀' },
  { id: 2, name: 'Marketing', icon: '⚡️' },
  { id: 3, name: 'Development', icon: '🛠️' },
];

const allowedLocales = [{ code: 'en', name: 'English' }];

const portalName = 'Chatwoot Help Center';

const meta = {
  currentPage: 1,
  allArticlesCount: articles.length,
  articlesCount: articles.length,
  mineArticlesCount: 2,
  draftArticlesCount: 1,
  archivedArticlesCount: 2,
};
</script>

<template>
  <Story title="Pages/HelpCenter/ArticlesPage" :layout="{ type: 'single' }">
    <Variant title="All Articles">
      <div class="w-full min-h-screen bg-n-background">
        <ArticlesPage
          :articles="articles"
          :categories="categories"
          :allowed-locales="allowedLocales"
          :portal-name="portalName"
          :meta="meta"
        />
      </div>
    </Variant>
  </Story>
</template>
