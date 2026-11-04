<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import microsoftClient from 'dashboard/api/channel/microsoftClient';
import googleClient from 'dashboard/api/channel/googleClient';
import SettingsSubPageHeader from '../../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

import { useAlert } from 'dashboard/composables';

const props = defineProps({
  provider: {
    type: String,
    required: true,
    validate: value => ['microsoft', 'google'].includes(value),
  },
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  submitButtonText: {
    type: String,
    required: true,
  },
  errorMessage: {
    type: String,
    required: true,
  },
});

const route = useRoute();
const { t } = useI18n();

const isRequestingAuthorization = ref(false);
// Microsoft only: address of a shared mailbox the signing-in account has Full Access + Send As on.
const sharedMailbox = ref('');

const supportsSharedMailbox = computed(() => props.provider === 'microsoft');

const client = computed(() => {
  if (props.provider === 'microsoft') {
    return microsoftClient;
  }

  return googleClient;
});

async function requestAuthorization() {
  try {
    isRequestingAuthorization.value = true;
    const mailbox = sharedMailbox.value.trim();
    const payload =
      supportsSharedMailbox.value && mailbox ? { email: mailbox } : undefined;
    const response = await client.value.generateAuthorization(payload);
    const {
      data: { url },
    } = response;

    window.location.href = url;
  } catch (error) {
    useAlert(props.errorMessage);
  } finally {
    isRequestingAuthorization.value = false;
  }
}

// Set by the Microsoft callback when the signed-in account could not open the shared mailbox.
const accessError = ref('');

onMounted(() => {
  if (route.query.error !== 'shared_mailbox_access') return;

  sharedMailbox.value = route.query.mailbox || '';
  accessError.value = t(
    'INBOX_MGMT.ADD.MICROSOFT.SHARED_MAILBOX.ACCESS_ERROR',
    {
      mailbox: sharedMailbox.value,
    }
  );
});
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <SettingsSubPageHeader
      :header-title="title"
      :header-content="description"
    />
    <form
      class="mt-6 flex flex-col items-start gap-4"
      @submit.prevent="requestAuthorization"
    >
      <p
        v-if="accessError"
        class="w-full max-w-lg mb-0 p-3 rounded-lg text-sm text-n-ruby-11 bg-n-ruby-2 outline outline-1 outline-n-ruby-5"
      >
        {{ accessError }}
      </p>
      <div v-if="supportsSharedMailbox" class="w-full max-w-lg">
        <Input
          v-model="sharedMailbox"
          type="email"
          :label="t('INBOX_MGMT.ADD.MICROSOFT.SHARED_MAILBOX.LABEL')"
          :placeholder="
            t('INBOX_MGMT.ADD.MICROSOFT.SHARED_MAILBOX.PLACEHOLDER')
          "
        />
        <p class="mt-1 mb-0 text-label-small text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.MICROSOFT.SHARED_MAILBOX.HELP') }}
        </p>
      </div>
      <NextButton
        :is-loading="isRequestingAuthorization"
        type="submit"
        solid
        blue
        :label="submitButtonText"
      />
    </form>
  </div>
</template>
