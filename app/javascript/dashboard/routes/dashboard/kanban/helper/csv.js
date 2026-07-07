/**
 * Exportação CSV do Kanban SDR AI.
 *
 * Gera o arquivo 100% no cliente a partir dos registros já carregados (portanto já
 * filtrados por permissão pelo backend). Usa `;` como separador e prefixo BOM para
 * abrir corretamente no Excel em português; strings com aspas/`;`/quebra de linha são
 * escapadas com aspas duplas.
 */
import {
  resolveStage,
  stageLabel,
  lostReasonLabel,
  LOST_STAGE,
  NEXT_ACTION_ATTRIBUTE_KEY,
  LOST_REASON_ATTRIBUTE_KEY,
} from '../config/stages';

const DELIMITER = ';';
const NOT_INFORMED = 'Não informado';

const HEADERS = [
  'ID',
  'Cliente',
  'Produto',
  'Volume',
  'Etapa',
  'Data de criação',
  'Última atualização',
  'Próxima ação',
  'Contato',
  'Telefone',
  'E-mail',
  'Responsável',
  'Motivo de perda',
];

const escapeCell = value => {
  const str =
    value === null || value === undefined ? '' : String(value);
  if (str.includes('"') || str.includes(DELIMITER) || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
};

const formatDate = seconds =>
  seconds
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(seconds * 1000))
    : '';

const formatVolume = raw => {
  const number = Number(raw);
  if (raw === undefined || raw === null || raw === '' || !Number.isFinite(number)) {
    return '';
  }
  return number.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
};

const orNotInformed = value =>
  value === undefined || value === null || value === '' ? NOT_INFORMED : value;

const rowFor = record => {
  const custom = record.custom_attributes || {};
  const sender = record.meta?.sender || {};
  const isLost = resolveStage(record) === LOST_STAGE;
  return [
    record.id,
    orNotInformed(sender.name),
    orNotInformed(custom.produto_interesse),
    orNotInformed(formatVolume(custom.valor_potencial)),
    stageLabel(resolveStage(record)),
    orNotInformed(formatDate(record.created_at)),
    orNotInformed(formatDate(record.last_activity_at)),
    orNotInformed(custom[NEXT_ACTION_ATTRIBUTE_KEY]),
    orNotInformed(sender.name),
    orNotInformed(sender.phone_number),
    orNotInformed(sender.email),
    orNotInformed(record.meta?.assignee?.name),
    // Motivo só faz sentido para perdidos; nos demais fica vazio (não "Não informado").
    isLost ? lostReasonLabel(custom[LOST_REASON_ATTRIBUTE_KEY]) : '',
  ];
};

export const buildKanbanCsv = records => {
  const lines = [HEADERS, ...records.map(rowFor)];
  const body = lines
    .map(cols => cols.map(escapeCell).join(DELIMITER))
    .join('\r\n');
  // BOM para o Excel reconhecer UTF-8 e não corromper acentos.
  return `﻿${body}`;
};

export const downloadKanbanCsv = (records, filename = 'kanban-sdr-ai.csv') => {
  const blob = new Blob([buildKanbanCsv(records)], {
    type: 'text/csv;charset=utf-8;',
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};
