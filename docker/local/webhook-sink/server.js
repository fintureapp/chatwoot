// Finture local — coletor de webhooks + Graph API (WhatsApp Cloud) simulada.
//
// Tudo que o Chatwoot local tenta "enviar para fora" e foi apontado para cá
// (webhook_url de inbox API, webhooks de conta, AgentBots, WHATSAPP_CLOUD_BASE_URL)
// é registrado e respondido com um payload plausível. Nada sai da máquina.
//
//   GET    /_health     -> ok
//   GET    /_requests   -> últimas requisições capturadas (JSON)
//   DELETE /_requests   -> limpa o histórico
//
// Sem dependências: só o módulo http do Node.
const http = require('http');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8080);
const MAX_ENTRIES = 500;
const MAX_BODY_LOG = 4096;
const captured = [];

const SENSITIVE_HEADERS = [
  'authorization',
  'cookie',
  'x-hub-signature-256',
  'x-chatwoot-signature',
  'api_access_token',
];

function maskHeaders(headers) {
  const out = {};
  Object.entries(headers).forEach(([key, value]) => {
    out[key] = SENSITIVE_HEADERS.includes(key.toLowerCase())
      ? '[mascarado]'
      : value;
  });
  return out;
}

function maskUrl(url) {
  return url.replace(
    /(access_token|api_key|token)=([^&]+)/gi,
    '$1=[mascarado]'
  );
}

function parseJson(raw) {
  try {
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

// Respostas no formato da Graph API para o provider whatsapp_cloud.
function graphResponse(method, path, json) {
  if (method === 'POST' && /\/messages$/.test(path)) {
    const to = json && json.to ? String(json.to) : '0000000000000';
    return {
      messaging_product: 'whatsapp',
      contacts: [{ input: to, wa_id: to }],
      messages: [
        {
          id: `wamid.LOCAL${crypto.randomBytes(12).toString('hex').toUpperCase()}`,
        },
      ],
    };
  }
  if (method === 'GET' && /\/message_templates/.test(path)) {
    return { data: [], paging: {} };
  }
  if (/\/subscribed_apps$/.test(path)) {
    return { success: true };
  }
  if (method === 'GET' && /\/phone_numbers/.test(path)) {
    return {
      data: [
        {
          id: 'local-phone-number-id',
          display_phone_number: '+55 00 90000-0000',
          verified_name: 'Finture Local',
        },
      ],
    };
  }
  return null;
}

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const raw = Buffer.concat(chunks).toString('utf8');
    const [path] = req.url.split('?');

    if (path === '/_health') return send(res, 200, { status: 'ok' });
    if (path === '/_requests' && req.method === 'GET')
      return send(res, 200, { count: captured.length, requests: captured });
    if (path === '/_requests' && req.method === 'DELETE') {
      captured.length = 0;
      return send(res, 200, { cleared: true });
    }

    const json = parseJson(raw);
    const entry = {
      id: crypto.randomUUID(),
      at: new Date().toISOString(),
      method: req.method,
      url: maskUrl(req.url),
      headers: maskHeaders(req.headers),
      body: json || raw.slice(0, MAX_BODY_LOG),
    };
    captured.push(entry);
    if (captured.length > MAX_ENTRIES) captured.shift();
    console.log(
      JSON.stringify({
        captured: entry.method,
        url: entry.url,
        at: entry.at,
        bytes: raw.length,
      })
    );

    const graph = graphResponse(req.method, path, json);
    return send(res, 200, graph || { success: true, captured_id: entry.id });
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[webhook-sink] ouvindo na porta ${PORT}`);
});
