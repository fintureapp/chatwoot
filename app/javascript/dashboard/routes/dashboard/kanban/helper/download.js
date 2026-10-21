// Dispara o download de um Blob recebido por XHR (a API exige os headers de
// autenticação do axios, então não dá para usar um <a href> direto).
export const downloadBlob = (blob, filename) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};

// Nome do arquivo vindo do Content-Disposition; cai no fallback se não houver.
export const filenameFromHeaders = (headers, fallback) => {
  const disposition = headers?.['content-disposition'] || '';
  const utf8 = disposition.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf8) return decodeURIComponent(utf8[1]);
  const plain = disposition.match(/filename="?([^";]+)"?/i);
  return plain ? plain[1] : fallback;
};
