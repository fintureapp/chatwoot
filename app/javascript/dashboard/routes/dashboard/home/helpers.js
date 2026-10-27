// Formatação da Home. Datas sempre em America/Sao_Paulo (o fuso da operação),
// qualquer que seja o fuso do navegador.
export const HOME_TIME_ZONE = 'America/Sao_Paulo';

const timeFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: HOME_TIME_ZONE,
  hour: '2-digit',
  minute: '2-digit',
});
const dateFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: HOME_TIME_ZONE,
  day: '2-digit',
  month: '2-digit',
});
const dateTimeFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: HOME_TIME_ZONE,
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
});

export const fmtTime = epoch => timeFormatter.format(new Date(epoch * 1000));
export const fmtDate = epoch => dateFormatter.format(new Date(epoch * 1000));
export const fmtDateTime = epoch =>
  dateTimeFormatter.format(new Date(epoch * 1000));

// Duração desde `epoch` até `nowEpoch`, curta: "12 min", "3 h", "4 d".
export const fmtElapsed = (epoch, nowEpoch) => {
  const minutes = Math.max(0, Math.floor((nowEpoch - epoch) / 60));
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours} h`;
  return `${Math.floor(hours / 24)} d`;
};

const weekdayFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: HOME_TIME_ZONE,
  weekday: 'short',
  day: '2-digit',
  month: '2-digit',
});
const hourFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: HOME_TIME_ZONE,
  hour: '2-digit',
});

// "qui., 23/10" (dica do gráfico) e "09h" (eixo do gráfico de hoje).
export const fmtWeekday = epoch =>
  weekdayFormatter.format(new Date(epoch * 1000));
export const fmtHour = epoch =>
  `${hourFormatter.format(new Date(epoch * 1000))}h`;

// Cor de um token do tema (`--brand`, `--slate-10`...) para quem não lê classe
// Tailwind, como o chart.js. Os tokens guardam "R G B".
export const themeColor = (token, alpha = 1) => {
  const rgb = getComputedStyle(document.documentElement)
    .getPropertyValue(`--${token}`)
    .trim();
  return `rgb(${rgb} / ${alpha})`;
};

// Variação contra o período anterior. null quando não há base para comparar.
export const deltaOf = (value, previous) => {
  if (value == null || previous == null) return null;
  if (previous === 0)
    return { direction: value > 0 ? 'up' : 'flat', pct: null };
  const pct = Math.round(((value - previous) / previous) * 100);
  if (pct === 0) return { direction: 'flat', pct: 0 };
  return { direction: pct > 0 ? 'up' : 'down', pct };
};
