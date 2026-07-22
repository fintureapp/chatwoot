// Configuração da cotação estruturada multi-produto (Fase 1 CRM Finture).
// Cada produto define os campos da sua seção; os valores vivem no jsonb `data`
// de finture_quotes (backend valida saúde PME: faixas ANS e acomodação).
// Labels ficam no i18n (KANBAN.QUOTE.*) — aqui só as chaves.

// Faixas etárias do padrão ANS (RN 63/2003) — mesmas chaves aceitas pelo backend.
export const ANS_AGE_BANDS = [
  '0-18',
  '19-23',
  '24-28',
  '29-33',
  '34-38',
  '39-43',
  '44-48',
  '49-53',
  '54-58',
  '59+',
];

export const QUOTE_ATTRIBUTE_KEY = 'sdr_quote_summary';
export const FOLLOW_UP_DUE_ATTRIBUTE_KEY = 'sdr_follow_up_due_at';

// type: text | number | select | boolean | textarea | lives (widget de faixas ANS)
export const QUOTE_PRODUCTS = [
  {
    value: 'saude_pme',
    labelKey: 'KANBAN.QUOTE.PRODUCTS.SAUDE_PME',
    totalValueLabelKey: 'KANBAN.QUOTE.TOTAL_VALUE.SAUDE_PME',
    fields: [
      {
        key: 'has_cnpj',
        type: 'boolean',
        labelKey: 'KANBAN.QUOTE.FIELDS.HAS_CNPJ',
      },
      { key: 'cnpj', type: 'text', labelKey: 'KANBAN.QUOTE.FIELDS.CNPJ' },
      {
        key: 'company_name',
        type: 'text',
        labelKey: 'KANBAN.QUOTE.FIELDS.COMPANY_NAME',
      },
      { key: 'city', type: 'text', labelKey: 'KANBAN.QUOTE.FIELDS.CITY' },
      {
        key: 'current_plan',
        type: 'text',
        labelKey: 'KANBAN.QUOTE.FIELDS.CURRENT_PLAN',
      },
      {
        key: 'hospital_preference',
        type: 'text',
        labelKey: 'KANBAN.QUOTE.FIELDS.HOSPITAL',
      },
      {
        key: 'accommodation',
        type: 'select',
        labelKey: 'KANBAN.QUOTE.FIELDS.ACCOMMODATION',
        options: [
          { value: 'enfermaria', labelKey: 'KANBAN.QUOTE.OPTIONS.ENFERMARIA' },
          {
            value: 'apartamento',
            labelKey: 'KANBAN.QUOTE.OPTIONS.APARTAMENTO',
          },
        ],
      },
      { key: 'copay', type: 'boolean', labelKey: 'KANBAN.QUOTE.FIELDS.COPAY' },
      { key: 'lives', type: 'lives', labelKey: 'KANBAN.QUOTE.FIELDS.LIVES' },
      { key: 'notes', type: 'textarea', labelKey: 'KANBAN.QUOTE.FIELDS.NOTES' },
    ],
  },
  {
    value: 'consorcio',
    labelKey: 'KANBAN.QUOTE.PRODUCTS.CONSORCIO',
    totalValueLabelKey: 'KANBAN.QUOTE.TOTAL_VALUE.CONSORCIO',
    fields: [
      {
        key: 'asset_type',
        type: 'select',
        labelKey: 'KANBAN.QUOTE.FIELDS.ASSET_TYPE',
        options: [
          { value: 'imovel', labelKey: 'KANBAN.QUOTE.OPTIONS.IMOVEL' },
          { value: 'veiculo', labelKey: 'KANBAN.QUOTE.OPTIONS.VEICULO' },
          { value: 'servicos', labelKey: 'KANBAN.QUOTE.OPTIONS.SERVICOS' },
        ],
      },
      {
        key: 'term_months',
        type: 'number',
        labelKey: 'KANBAN.QUOTE.FIELDS.TERM_MONTHS',
      },
      {
        key: 'down_payment',
        type: 'number',
        labelKey: 'KANBAN.QUOTE.FIELDS.DOWN_PAYMENT',
      },
      { key: 'notes', type: 'textarea', labelKey: 'KANBAN.QUOTE.FIELDS.NOTES' },
    ],
  },
  {
    value: 'seguros',
    labelKey: 'KANBAN.QUOTE.PRODUCTS.SEGUROS',
    totalValueLabelKey: 'KANBAN.QUOTE.TOTAL_VALUE.SEGUROS',
    fields: [
      {
        key: 'insurance_type',
        type: 'select',
        labelKey: 'KANBAN.QUOTE.FIELDS.INSURANCE_TYPE',
        options: [
          { value: 'vida', labelKey: 'KANBAN.QUOTE.OPTIONS.VIDA' },
          { value: 'auto', labelKey: 'KANBAN.QUOTE.OPTIONS.AUTO' },
          {
            value: 'residencial',
            labelKey: 'KANBAN.QUOTE.OPTIONS.RESIDENCIAL',
          },
          {
            value: 'empresarial',
            labelKey: 'KANBAN.QUOTE.OPTIONS.EMPRESARIAL',
          },
          { value: 'outros', labelKey: 'KANBAN.QUOTE.OPTIONS.OUTROS' },
        ],
      },
      {
        key: 'current_insurer',
        type: 'text',
        labelKey: 'KANBAN.QUOTE.FIELDS.CURRENT_INSURER',
      },
      {
        key: 'insured_amount',
        type: 'number',
        labelKey: 'KANBAN.QUOTE.FIELDS.INSURED_AMOUNT',
      },
      { key: 'notes', type: 'textarea', labelKey: 'KANBAN.QUOTE.FIELDS.NOTES' },
    ],
  },
  {
    value: 'credito',
    labelKey: 'KANBAN.QUOTE.PRODUCTS.CREDITO',
    totalValueLabelKey: 'KANBAN.QUOTE.TOTAL_VALUE.CREDITO',
    fields: [
      {
        key: 'credit_type',
        type: 'select',
        labelKey: 'KANBAN.QUOTE.FIELDS.CREDIT_TYPE',
        options: [
          { value: 'consignado', labelKey: 'KANBAN.QUOTE.OPTIONS.CONSIGNADO' },
          { value: 'pessoal', labelKey: 'KANBAN.QUOTE.OPTIONS.PESSOAL' },
          {
            value: 'imobiliario',
            labelKey: 'KANBAN.QUOTE.OPTIONS.IMOBILIARIO',
          },
          {
            value: 'capital_giro',
            labelKey: 'KANBAN.QUOTE.OPTIONS.CAPITAL_GIRO',
          },
        ],
      },
      {
        key: 'term_months',
        type: 'number',
        labelKey: 'KANBAN.QUOTE.FIELDS.TERM_MONTHS',
      },
      {
        key: 'collateral',
        type: 'text',
        labelKey: 'KANBAN.QUOTE.FIELDS.COLLATERAL',
      },
      { key: 'notes', type: 'textarea', labelKey: 'KANBAN.QUOTE.FIELDS.NOTES' },
    ],
  },
];

export const quoteProduct = value =>
  QUOTE_PRODUCTS.find(product => product.value === value);
