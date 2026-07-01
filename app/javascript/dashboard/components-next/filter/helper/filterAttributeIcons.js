/**
 * Shared helpers to make the attribute picker in FilterSelect richer: a leading icon per
 * attribute and grouped, non-clickable section headers. Used by the conversation, contact and
 * automation filter builders so they stay visually consistent.
 */

// Icon per known standard / additional attribute key (conversation + contact filters).
const ATTRIBUTE_ICONS = {
  // Contact attributes
  name: 'i-lucide-user',
  email: 'i-lucide-mail',
  phone_number: 'i-lucide-phone',
  identifier: 'i-lucide-fingerprint',
  country_code: 'i-lucide-flag',
  city: 'i-lucide-map-pin',
  company_name: 'i-lucide-building-2',
  blocked: 'i-lucide-ban',
  // Conversation attributes
  status: 'i-lucide-circle-dot',
  priority: 'i-lucide-signal-high',
  assignee_id: 'i-lucide-user-round',
  inbox_id: 'i-lucide-inbox',
  team_id: 'i-lucide-users-round',
  contact_id: 'i-lucide-contact',
  display_id: 'i-lucide-hash',
  campaign_id: 'i-lucide-megaphone',
  browser_language: 'i-lucide-globe',
  conversation_language: 'i-lucide-languages',
  referer: 'i-lucide-link',
  // Shared
  labels: 'i-lucide-tags',
  created_at: 'i-lucide-calendar',
  last_activity_at: 'i-lucide-activity',
};

// Icon per custom-attribute display type.
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
 * Resolve the leading icon for a single filter type.
 * @param {Object} type - A FilterType entry.
 * @returns {string} The icon class to render.
 */
export const getAttributeIcon = type => {
  if (type.attributeModel === 'customAttributes') {
    return CUSTOM_TYPE_ICONS[type.attributeDisplayType] || DEFAULT_ICON;
  }
  return ATTRIBUTE_ICONS[type.attributeKey] || DEFAULT_ICON;
};

// Order the groups appear in, keyed by attributeModel, with their i18n label keys.
const GROUPS = [
  { model: 'standard', label: 'FILTER.GROUPS.STANDARD_FILTERS' },
  { model: 'additional', label: 'FILTER.GROUPS.ADDITIONAL_FILTERS' },
  { model: 'customAttributes', label: 'FILTER.GROUPS.CUSTOM_ATTRIBUTES' },
];

/**
 * Attach a leading icon to each filter type and split them into grouped sections separated by
 * disabled header entries (which FilterSelect renders as non-clickable section titles).
 * @param {Object[]} filterTypes - Flat list of FilterType entries.
 * @param {Function} t - vue-i18n translate function.
 * @returns {Object[]} Grouped list with header + icon-enriched entries.
 */
export const groupFilterTypes = (filterTypes, t) => {
  const withIcon = type => ({
    ...type,
    icon: type.icon || getAttributeIcon(type),
  });
  const knownModels = GROUPS.map(group => group.model);

  const grouped = GROUPS.flatMap(({ model, label }) => {
    const group = filterTypes.filter(
      type => (type.attributeModel || 'standard') === model
    );
    if (!group.length) return [];
    return [
      { value: `__group_${model}`, label: t(label), disabled: true },
      ...group.map(withIcon),
    ];
  });

  // Append any attribute with an unexpected model rather than dropping it silently.
  const ungrouped = filterTypes.filter(
    type => !knownModels.includes(type.attributeModel || 'standard')
  );

  return [...grouped, ...ungrouped.map(withIcon)];
};
