// Agrupa os cards do board por CONTATO (um card por número), colapsando as
// conversas duplicadas do mesmo contato em um único card "primário" (o de
// atividade mais recente) + um histórico dos demais atendimentos.
//
// Motivação: cada vez que um número é resolvido e reaberto, o Chatwoot pode
// gerar uma conversa nova. Como o board mostra 1 card por conversa, o mesmo
// número aparecia várias vezes, bagunçando a coluna. Aqui colapsamos por número.
//
// Chave de agrupamento: id do contato (meta.sender.id) quando existir; senão o
// telefone normalizado (só dígitos); senão a própria conversa (não agrupa).
// Assim, números iguais viram um card só; registros sem contato/telefone ficam
// isolados (cada um seu card), nunca colapsados por engano.

const digitsOnly = value => String(value ?? '').replace(/\D/g, '');

export const contactKeyOf = record => {
  const sender = record?.meta?.sender || {};
  const id = sender.id;
  if (id !== null && id !== undefined && id !== '') return `contact:${id}`;
  const phone = digitsOnly(sender.phone_number);
  if (phone) return `phone:${phone}`;
  return `conv:${record?.id}`;
};

// Mais recente primeiro; empate por created_at (também desc).
const moreRecentFirst = (a, b) =>
  (b.last_activity_at || 0) - (a.last_activity_at || 0) ||
  (b.created_at || 0) - (a.created_at || 0);

const toHistoryEntry = record => ({
  id: record.id,
  at: record.last_activity_at || record.created_at || 0,
  stage: record.custom_attributes?.sdr_stage || '',
  outcome: record.custom_attributes?.sdr_outcome || '',
  status: record.status || '',
});

// Recebe os registros já filtrados e devolve 1 registro por contato. O card
// primário preserva todos os campos originais (id, custom_attributes, meta…),
// então drag/etapa/desfecho continuam agindo sobre a conversa mais recente.
// `groupCount` = total de atendimentos do número; `groupHistory` = os demais
// (mais recente → mais antigo), para o rodapé do card.
export const groupRecordsByContact = records => {
  const buckets = new Map();
  (records || []).forEach(record => {
    const key = contactKeyOf(record);
    if (buckets.has(key)) buckets.get(key).push(record);
    else buckets.set(key, [record]);
  });

  return [...buckets.values()].map(bucket => {
    if (bucket.length === 1) {
      return { ...bucket[0], groupCount: 1, groupHistory: [] };
    }
    const [primary, ...rest] = [...bucket].sort(moreRecentFirst);
    return {
      ...primary,
      groupCount: bucket.length,
      groupHistory: rest.map(toHistoryEntry),
    };
  });
};
