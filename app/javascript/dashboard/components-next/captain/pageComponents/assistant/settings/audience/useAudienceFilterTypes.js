import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useContactFilterContext } from 'dashboard/components-next/filter/contactProvider.js';
import { useOperators } from 'dashboard/components-next/filter/operators.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages.js';

// Icons for the standard contact attributes, keyed by attribute key.
const STANDARD_ICONS = {
  name: 'i-lucide-user',
  email: 'i-lucide-mail',
  phone_number: 'i-lucide-phone',
  identifier: 'i-lucide-fingerprint',
  country_code: 'i-lucide-flag',
  city: 'i-lucide-map-pin',
  company_name: 'i-lucide-building-2',
  created_at: 'i-lucide-calendar',
  last_activity_at: 'i-lucide-activity',
  blocked: 'i-lucide-ban',
  labels: 'i-lucide-tags',
  browser_language: 'i-lucide-globe',
  conversation_language: 'i-lucide-languages',
};

// Icons for custom attributes, keyed by the attribute's display type.
const CUSTOM_TYPE_ICONS = {
  text: 'i-lucide-type',
  number: 'i-lucide-hash',
  currency: 'i-lucide-banknote',
  percent: 'i-lucide-percent',
  link: 'i-lucide-link',
  date: 'i-lucide-calendar',
  list: 'i-lucide-list',
  checkbox: 'i-lucide-square-check',
};

const DEFAULT_ICON = 'i-lucide-tag';

/**
 * Filter types for a Captain assistant audience: contact attributes (reused from the contact
 * segment builder) plus the two conversation language fields. Each option carries an icon, and the
 * options are split into grouped sections (contact / conversation / custom) via disabled headers,
 * which FilterSelect renders as non-clickable section titles.
 *
 * @returns {{ filterTypes: import('vue').ComputedRef<Array> }}
 */
export function useAudienceFilterTypes() {
  const { t } = useI18n();
  const { filterTypes: contactFilterTypes } = useContactFilterContext();
  const { equalityOperators } = useOperators();
  const contactAttributes = useMapGetter('attributes/getContactAttributes');

  // Map custom attribute key -> display type, so each custom option gets a type-based icon.
  const customTypeByKey = computed(() =>
    (contactAttributes.value || []).reduce((acc, attr) => {
      acc[attr.attributeKey] = attr.attributeDisplayType;
      return acc;
    }, {})
  );

  // Conversation-level attributes: the logged-in (HMAC verified) flag and the language fields.
  // Languages use a searchable dropdown (same option list as automation rules), not free text.
  const conversationFilterTypes = computed(() => [
    {
      attributeKey: 'hmac_verified',
      value: 'hmac_verified',
      attributeName: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.LOGGED_IN'),
      label: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.LOGGED_IN'),
      icon: 'i-lucide-user-check',
      inputType: 'searchSelect',
      options: [
        {
          id: 'true',
          name: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.LOGGED_IN_TRUE'),
        },
        {
          id: 'false',
          name: t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.LOGGED_IN_FALSE'),
        },
      ],
      dataType: 'text',
      filterOperators: equalityOperators.value,
      attributeModel: 'additional',
    },
    ...['browser_language', 'conversation_language'].map(key => ({
      attributeKey: key,
      value: key,
      attributeName: t(`CAPTAIN.ASSISTANTS.FORM.AUDIENCE.${key.toUpperCase()}`),
      label: t(`CAPTAIN.ASSISTANTS.FORM.AUDIENCE.${key.toUpperCase()}`),
      icon: STANDARD_ICONS[key],
      inputType: 'searchSelect',
      options: languages,
      dataType: 'text',
      filterOperators: equalityOperators.value,
      attributeModel: 'additional',
    })),
  ]);

  const header = (id, label) => ({
    value: `__group_${id}`,
    label,
    disabled: true,
  });

  const filterTypes = computed(() => {
    const standard = [];
    const custom = [];

    contactFilterTypes.value.forEach(type => {
      if (type.attributeModel === 'customAttributes') {
        // Only contact-model custom attributes belong here; never conversation/company ones.
        if (!(type.attributeKey in customTypeByKey.value)) return;
        const displayType = customTypeByKey.value[type.attributeKey];
        custom.push({
          ...type,
          icon: CUSTOM_TYPE_ICONS[displayType] || DEFAULT_ICON,
        });
      } else {
        standard.push({
          ...type,
          icon: STANDARD_ICONS[type.attributeKey] || DEFAULT_ICON,
        });
      }
    });

    return [
      header('contact', t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.GROUP_CONTACT')),
      ...standard,
      header(
        'conversation',
        t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.GROUP_CONVERSATION')
      ),
      ...conversationFilterTypes.value,
      ...(custom.length
        ? [
            header(
              'custom',
              t('CAPTAIN.ASSISTANTS.FORM.AUDIENCE.GROUP_CUSTOM')
            ),
            ...custom,
          ]
        : []),
    ];
  });

  return { filterTypes };
}
