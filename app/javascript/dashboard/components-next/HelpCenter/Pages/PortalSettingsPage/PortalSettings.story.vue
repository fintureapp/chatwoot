<script setup>
import PortalSettings from './PortalSettings.vue';

// `slug` matches the route the stories harness seeds (portals/chatwoot), so
// PortalSettings resolves an active portal and renders the settings forms.
const portals = [
  {
    id: 1,
    name: 'Chatwoot Help Center',
    slug: 'chatwoot',
    header_text: 'How can we help you today?',
    page_title: 'Chatwoot Help Center',
    homepage_link: 'https://www.chatwoot.com',
    custom_domain: '',
    config: {},
    ssl_settings: {},
  },
];
</script>

<template>
  <Story title="Pages/HelpCenter/PortalSettings" :layout="{ type: 'single' }">
    <Variant title="Default">
      <div class="w-[1000px] min-h-screen bg-n-background">
        <PortalSettings :portals="portals" :is-fetching="false" />
      </div>
    </Variant>
  </Story>
</template>
