// Histórico do Kanban SDR agrupado por CONTATO: um número = uma linha, com
// todos os atendimentos fechados dele. O detalhe (todas as conversas, inclusive
// de outras caixas, com abertura/fechamento/resumo) vem do modal de linha do
// tempo; aqui só montamos o resumo da linha.
import { contactKeyOf } from './grouping';

// Quando o atendimento fechou: desfecho ganho/perdido (comercial) ou a última
// atividade da conversa resolvida (operacional).
export const closedAtOf = record =>
  Number(record?.custom_attributes?.sdr_outcome_at) ||
  record?.last_activity_at ||
  0;

const mostRecentClosedFirst = (a, b) => closedAtOf(b) - closedAtOf(a);

export const groupHistoryByContact = records => {
  const buckets = new Map();
  (records || []).forEach(record => {
    const key = contactKeyOf(record);
    if (buckets.has(key)) buckets.get(key).push(record);
    else buckets.set(key, [record]);
  });

  return [...buckets.entries()]
    .map(([key, bucket]) => {
      const sorted = [...bucket].sort(mostRecentClosedFirst);
      const outcomes = sorted.map(r => r.custom_attributes?.sdr_outcome);
      return {
        key,
        contact: sorted[0].meta?.sender || {},
        latest: sorted[0],
        records: sorted,
        count: sorted.length,
        lastClosedAt: closedAtOf(sorted[0]),
        wonCount: outcomes.filter(o => o === 'won').length,
        lostCount: outcomes.filter(o => o === 'lost').length,
      };
    })
    .sort((a, b) => b.lastClosedAt - a.lastClosedAt);
};

// Janela em que um resumo ausente ainda é "em processamento": o fluxo n8n roda
// no resolve e leva segundos. Passado isso, o resumo não vem mais (a IA não
// achou conteúdo, a conversa é anterior ao fluxo ou a caixa não gera resumo).
export const SUMMARY_GRACE_SECONDS = 30 * 60;

// 'ready' | 'open' (atendimento em andamento) | 'pending' | 'missing'.
export const summaryStateOf = ({ resumo, closedAt, now }) => {
  if (resumo) return 'ready';
  if (!closedAt) return 'open';
  return now - closedAt < SUMMARY_GRACE_SECONDS ? 'pending' : 'missing';
};
