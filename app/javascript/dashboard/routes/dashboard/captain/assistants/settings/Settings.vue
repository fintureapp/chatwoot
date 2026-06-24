<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import SettingsHeader from 'dashboard/components-next/captain/pageComponents/settings/SettingsHeader.vue';
import AssistantBasicSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantBasicSettingsForm.vue';
import AssistantSystemSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue';
import AssistantAudienceForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantAudienceForm.vue';
import AssistantScheduleForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantScheduleForm.vue';
import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';

const { t } = useI18n();
const { isCloudFeatureEnabled } = useAccount();

const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);
const route = useRoute();
const router = useRouter();
const store = useStore();

const deleteAssistantDialog = ref(null);

const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const assistants = useMapGetter('captainAssistants/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingItem);
const assistantId = computed(() => Number(route.params.assistantId));
const assistant = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const activeSection = ref('basic');

const navItems = computed(() => {
  const items = [
    {
      id: 'basic',
      label: t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.TITLE'),
    },
    {
      id: 'system',
      label: t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.TITLE'),
    },
    { id: 'audience', label: t('CAPTAIN.ASSISTANTS.SETTINGS.AUDIENCE.TITLE') },
    { id: 'schedule', label: t('CAPTAIN.ASSISTANTS.SETTINGS.SCHEDULE.TITLE') },
  ];

  if (isCaptainV2Enabled.value) {
    items.push(
      {
        routeName: 'captain_assistants_guardrails_index',
        label: t(
          'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.GUARDRAILS.TITLE'
        ),
      },
      {
        routeName: 'captain_assistants_guidelines_index',
        label: t(
          'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.RESPONSE_GUIDELINES.TITLE'
        ),
      }
    );
  }

  return items;
});

const handleNavClick = item => {
  if (item.routeName) {
    router.push({
      name: item.routeName,
      params: {
        accountId: route.params.accountId,
        assistantId: assistantId.value,
      },
    });
    return;
  }
  activeSection.value = item.id;
};

const handleSubmit = async updatedAssistant => {
  try {
    await store.dispatch('captainAssistants/update', {
      id: assistantId.value,
      ...updatedAssistant,
    });
    useAlert(t('CAPTAIN.ASSISTANTS.EDIT.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const handleDelete = () => {
  deleteAssistantDialog.value.dialogRef.open();
};

const handleDeleteSuccess = () => {
  // Get remaining assistants after deletion
  const remainingAssistants = assistants.value.filter(
    a => a.id !== assistantId.value
  );

  if (remainingAssistants.length > 0) {
    // Navigate to the first available assistant's settings
    const nextAssistant = remainingAssistants[0];
    router.push({
      name: 'captain_assistants_settings_index',
      params: {
        accountId: route.params.accountId,
        assistantId: nextAssistant.id,
      },
    });
  } else {
    // No assistants left, redirect to create assistant page
    router.push({
      name: 'captain_assistants_create_index',
      params: { accountId: route.params.accountId },
    });
  }
};
</script>

<template>
  <PageLayout
    :is-fetching="isFetching"
    :show-pagination-footer="false"
    :show-know-more="false"
  >
    <template #body>
      <div class="flex gap-8 pb-8">
        <nav
          class="sticky self-start flex flex-col flex-shrink-0 w-48 gap-1 top-0"
        >
          <button
            v-for="item in navItems"
            :key="item.id ?? item.routeName"
            type="button"
            class="px-3 py-2 text-sm text-left rounded-lg transition-colors"
            :class="
              activeSection === item.id
                ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="handleNavClick(item)"
          >
            {{ item.label }}
          </button>
        </nav>

        <div class="flex flex-col flex-1 min-w-0 gap-6">
          <section v-if="activeSection === 'basic'" class="flex flex-col gap-6">
            <SettingsHeader
              :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.TITLE')"
              :description="
                t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.DESCRIPTION')
              "
            />
            <AssistantBasicSettingsForm
              :assistant="assistant"
              @submit="handleSubmit"
            />
            <span class="w-full h-px mt-2 bg-n-weak" />
            <div class="flex items-end justify-between w-full gap-4">
              <div class="flex flex-col gap-2">
                <h6 class="text-base font-medium text-n-slate-12">
                  {{ t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.TITLE') }}
                </h6>
                <span class="text-sm text-n-slate-11">
                  {{ t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.DESCRIPTION') }}
                </span>
              </div>
              <div class="flex-shrink-0">
                <Button
                  :label="
                    t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.BUTTON_TEXT', {
                      assistantName: assistant.name,
                    })
                  "
                  color="ruby"
                  class="max-w-56 !w-fit"
                  @click="handleDelete"
                />
              </div>
            </div>
          </section>

          <section
            v-else-if="activeSection === 'system'"
            class="flex flex-col gap-6"
          >
            <SettingsHeader
              :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.TITLE')"
              :description="
                t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.DESCRIPTION')
              "
            />
            <AssistantSystemSettingsForm
              :assistant="assistant"
              @submit="handleSubmit"
            />
          </section>

          <section
            v-else-if="activeSection === 'audience'"
            class="flex flex-col gap-6"
          >
            <SettingsHeader
              :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.AUDIENCE.TITLE')"
              :description="
                t('CAPTAIN.ASSISTANTS.SETTINGS.AUDIENCE.DESCRIPTION')
              "
            />
            <AssistantAudienceForm
              :assistant="assistant"
              @submit="handleSubmit"
            />
          </section>

          <section
            v-else-if="activeSection === 'schedule'"
            class="flex flex-col gap-6"
          >
            <SettingsHeader
              :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.SCHEDULE.TITLE')"
              :description="
                t('CAPTAIN.ASSISTANTS.SETTINGS.SCHEDULE.DESCRIPTION')
              "
            />
            <AssistantScheduleForm
              :assistant="assistant"
              @submit="handleSubmit"
            />
          </section>
        </div>
      </div>
    </template>
    <DeleteDialog
      v-if="assistant"
      ref="deleteAssistantDialog"
      :entity="assistant"
      type="Assistants"
      translation-key="ASSISTANTS"
      @delete-success="handleDeleteSuccess"
    />
  </PageLayout>
</template>
