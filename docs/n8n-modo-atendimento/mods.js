// Ajustes dos fluxos de triagem (Triagem Parceiros e Suporte Clientes) para o modo
// de atendimento autoritativo do Chatwoot. Compatível com o Chatwoot atual (sem
// finture_attendance) e com o novo.
const TOKEN_CRED = {
  Bvfj: 'Chatwoot API - leitura (n8n)',
  RzeB: 'Chatwoot API - Bia (envio)',
};
const ANTHROPIC_CRED = 'Anthropic API (x-api-key)';

const REVISAO = "$('Avaliar Estado Atendimento').item.json.revisao";
const REG = "$('Registrar Handoff (Chatwoot)').item.json";

function byName(wf, name) {
  const n = wf.nodes.find(x => x.name === name);
  if (!n) throw new Error('nó não encontrado: ' + name);
  return n;
}

function patch(str, from, to, label) {
  if (!str.includes(from)) throw new Error('âncora não encontrada (' + label + '): ' + from.slice(0, 80));
  return str.replace(from, to);
}

const AVALIAR_ESTADO = `
// Estado autoritativo do Chatwoot (finture_attendance) quando disponível; senão a
// regra antiga (atributo modo_atendimento + etiqueta). Se a consulta falhar, o bot
// fica quieto: na dúvida, não responde.
const g = $input.first().json || {};
const conv = g.payload || g;
const leituraOk = !g.error && !!(conv && conv.id);
const fa = (leituraOk && conv.finture_attendance) || null;
const ca = conv.custom_attributes || (conv.meta && conv.meta.custom_attributes) || {};
const modoLegado = String(ca.modo_atendimento || '').toLowerCase().trim();
let labels = conv.labels || (conv.meta && conv.meta.labels) || [];
if (!Array.isArray(labels)) labels = [];
const labelsLower = labels.map(function(l){ return String(l).toLowerCase(); });
const temLabel = labelsLower.indexOf('atendimento_humano') !== -1;
const modo = fa && fa.mode ? String(fa.mode) : modoLegado;
let emAtendimentoHumano = fa ? fa.mode === 'humano' : (modoLegado === 'humano' || (temLabel && modoLegado !== 'ia'));
if (!leituraOk) emAtendimentoHumano = true;
const revisao = fa && Number.isInteger(fa.revision) ? fa.revision : null;
const rc = (fa && fa.resume_context) || null;
const retomada = (fa && fa.source === 'dashboard_return' && rc && (rc.reason || rc.pending_notes)) ? rc : null;
const dados = $('Extrair Dados Chatwoot').first().json;
return [{ json: Object.assign({}, dados, { emAtendimentoHumano, guardFalhou: !leituraOk, modoAtendimento: modo, revisao, retomada, labelsAtuais: labels, customAttrsAtuais: ca }) }];
`;

const LOG_BLOQUEIO = `
const d = $input.first().json;
return [{ json: { skipped: d.guardFalhou ? 'falha_consulta_estado' : 'atendimento_humano', conversationId: d.conversationId, modoAtendimento: d.modoAtendimento } }];
`;

const MOTOR_RETOMADA = `
// Retomada: humano devolveu a conversa à IA (botão "Devolver à IA"). Sem estado de
// triagem no Redis, NÃO reapresenta o menu: segue pelo Haiku com o motivo e as
// pendências anotadas pelo atendente.
const _ret = guard.retomada || null;
if (!estado && _ret) {
  const _tri = _ret.triage || {};
  return [{ json: Object.assign({}, base, { acao: 'interpretar', etapaAtual: 'retomada', tipoDemandaAtual: _tri.tipo || null, produtoAtual: _tri.produto || null, retomada: _ret }) }];
}

if (!estado) {`;

const HAIKU_RETOMADA = `const _ret = motor.retomada || null;
const _retBlock = _ret ? ('\\n\\nRETOMADA: esta conversa estava com um atendente humano, que a devolveu para voce. Motivo da devolucao: ' + (_ret.reason || '-') + '. Pendencias anotadas pelo atendente: ' + (_ret.pending_notes || 'nenhuma') + (_ret.triage ? ('. Triagem anterior: ' + JSON.stringify(_ret.triage)) : '') + '. NAO reapresente o menu e NAO recomece a triagem do zero: continue a partir desse contexto. Se a mensagem trouxer a pendencia resolvida ou um pedido novo, encaminhe (handoff) ao time adequado com um resumo que inclua a pendencia.') : '';
const claudeBody = {`;

function useCredentials(node) {
  const p = node.parameters;
  const headers = (p.headerParameters && p.headerParameters.parameters) || [];
  let credName = null;
  const rest = headers.filter(h => {
    if (h.name === 'api_access_token') {
      const tail = String(h.value).slice(-4);
      credName = TOKEN_CRED[tail];
      if (!credName) throw new Error('token desconhecido em ' + node.name);
      return false;
    }
    if (h.name === 'x-api-key') { credName = ANTHROPIC_CRED; return false; }
    return true;
  });
  if (!credName) return;
  p.authentication = 'genericCredentialType';
  p.genericAuthType = 'httpHeaderAuth';
  if (rest.length) {
    p.headerParameters = { parameters: rest };
  } else {
    delete p.headerParameters;
    p.sendHeaders = false;
  }
  node.credentials = { httpHeaderAuth: credName };
}

module.exports = function apply(wf) {
  // 1) Guard: falha na consulta = bot quieto; lê o estado autoritativo e a revisão.
  byName(wf, 'Avaliar Estado Atendimento').parameters.jsCode = AVALIAR_ESTADO;
  byName(wf, 'Log Bloqueio Humano').parameters.jsCode = LOG_BLOQUEIO;

  // 2) Retomada sem menu, com as pendências no prompt do Haiku.
  const motor = byName(wf, 'Motor Triagem');
  motor.parameters.jsCode = patch(motor.parameters.jsCode, '\nif (!estado) {', MOTOR_RETOMADA, 'motor');
  const haiku = byName(wf, 'Montar Body Haiku');
  haiku.parameters.jsCode = patch(haiku.parameters.jsCode, 'const claudeBody = {', HAIKU_RETOMADA, 'haiku-ret');
  haiku.parameters.jsCode = patch(haiku.parameters.jsCode, "content: userMsg }", "content: userMsg + _retBlock }", 'haiku-msg');

  // 3) Envio do bot leva a revisão; recusado (alguém assumiu) = para sem toggle.
  const menu = byName(wf, 'Enviar Menu Chatwoot');
  menu.parameters.jsonBody = patch(menu.parameters.jsonBody,
    "JSON.stringify({ content: $('Preparar Envio Triagem').item.json.mensagemBot, message_type: 'outgoing', private: false })",
    "JSON.stringify(Object.assign({ content: $('Preparar Envio Triagem').item.json.mensagemBot, message_type: 'outgoing', private: false }, " +
      REVISAO + " !== null ? { content_attributes: { finture_bot_revision: " + REVISAO + " } } : {}))",
    'menu');
  menu.onError = 'continueErrorOutput';
  const toggleTriagem = byName(wf, 'Toggle Status Open (Triagem)');
  wf.nodes.push({
    parameters: { respondWith: 'text', responseBody: 'SKIP-ENVIO-RECUSADO', options: { responseCode: 200 } },
    name: 'Responder OK (Envio Recusado)', type: 'n8n-nodes-base.respondToWebhook', typeVersion: 1.5,
    position: [toggleTriagem.position[0], toggleTriagem.position[1] - 192],
  });
  wf.connections['Enviar Menu Chatwoot'] = { main: [[{ node: 'Toggle Status Open (Triagem)', type: 'main', index: 0 }], [{ node: 'Responder OK (Envio Recusado)', type: 'main', index: 0 }]] };

  // 4) Handoff pelo endpoint novo (bot_handoff); 409 = humano já assumiu (para);
  //    outro erro (ex.: Chatwoot ainda sem o endpoint) = caminho antigo.
  const prep = byName(wf, 'Preparar Handoff');
  prep.parameters.jsCode = patch(prep.parameters.jsCode, '  handoffKey: handoffKey\n} }];',
    "  handoffKey: handoffKey,\n  motivoHandoff: d.motivo || 'Triagem',\n  triagem: { tipo: d.tipoDemanda || null, produto: d.produto || null, descricao: String(d.descricao || '').slice(0, 500), time: teamName }\n} }];",
    'prep');
  const legacy = byName(wf, 'Set Custom Attr Humano');
  const [lx, ly] = legacy.position;
  wf.nodes.push({
    parameters: {
      method: 'POST',
      url: "=https://chatwoot-web.victorioushill-d6770e72.westeurope.azurecontainerapps.io/api/v1/accounts/{{ $('Extrair Dados Chatwoot').item.json.accountId }}/conversations/{{ $('Extrair Dados Chatwoot').item.json.conversationId }}/finture_attendance/bot_handoff",
      sendHeaders: true,
      headerParameters: { parameters: [{ name: 'api_access_token', value: 'xxxxBvfj' }, { name: 'Content-Type', value: 'application/json' }] },
      sendBody: true,
      specifyBody: 'json',
      jsonBody: "={{ JSON.stringify({ reason: $('Preparar Handoff').item.json.motivoHandoff, expected_revision: " + REVISAO + ", triage: $('Preparar Handoff').item.json.triagem }) }}",
      options: { timeout: 15000, response: { response: { neverError: true, fullResponse: true } } },
    },
    name: 'Registrar Handoff (Chatwoot)', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.4,
    position: [lx, ly - 400], onError: 'continueRegularOutput',
  });
  const ifCond = (id, left) => ({
    conditions: {
      options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ id, leftValue: left, rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } }],
      combinator: 'and',
    },
    options: {},
  });
  wf.nodes.push({
    parameters: ifCond('reg-ok', '={{ Number($json.statusCode) >= 200 && Number($json.statusCode) < 300 }}'),
    name: 'Handoff Registrado?', type: 'n8n-nodes-base.if', typeVersion: 2.3, position: [lx + 224, ly - 400],
  });
  wf.nodes.push({
    parameters: ifCond('reg-409', '={{ Number($json.statusCode) === 409 }}'),
    name: 'Humano Ja Assumiu?', type: 'n8n-nodes-base.if', typeVersion: 2.3, position: [lx + 448, ly - 256],
  });
  wf.nodes.push({
    parameters: { respondWith: 'text', responseBody: 'HANDOFF-HUMANO-JA-ASSUMIU', options: { responseCode: 200 } },
    name: 'Responder OK (Humano Ja Assumiu)', type: 'n8n-nodes-base.respondToWebhook', typeVersion: 1.5, position: [lx + 672, ly - 352],
  });
  const dup = wf.connections['Handoff Duplicado?'].main;
  dup[1] = [{ node: 'Registrar Handoff (Chatwoot)', type: 'main', index: 0 }];
  wf.connections['Registrar Handoff (Chatwoot)'] = { main: [[{ node: 'Handoff Registrado?', type: 'main', index: 0 }]] };
  wf.connections['Handoff Registrado?'] = { main: [
    [{ node: 'Toggle Status Open (Handoff)', type: 'main', index: 0 }],
    [{ node: 'Humano Ja Assumiu?', type: 'main', index: 0 }],
  ] };
  wf.connections['Humano Ja Assumiu?'] = { main: [
    [{ node: 'Responder OK (Humano Ja Assumiu)', type: 'main', index: 0 }],
    [{ node: 'Set Custom Attr Humano', type: 'main', index: 0 }],
  ] };
  legacy.position = [lx + 672, ly - 160];
  const labels = byName(wf, 'POST Labels Handoff');
  labels.position = [lx + 896, ly - 160];

  const conf = byName(wf, 'Enviar Confirmacao Handoff');
  conf.parameters.jsonBody = patch(conf.parameters.jsonBody,
    "JSON.stringify({ content: $('Preparar Handoff').item.json.confirmacao, message_type: 'outgoing', private: false })",
    "JSON.stringify(Object.assign({ content: $('Preparar Handoff').item.json.confirmacao, message_type: 'outgoing', private: false }, " +
      "(Number(" + REG + ".statusCode) >= 200 && Number(" + REG + ".statusCode) < 300 && " + REG + ".body && " + REG + ".body.attendance) ? " +
      "{ content_attributes: { finture_bot_revision: " + REG + ".body.attendance.revision } } : {}))",
    'confirmacao');

  // 5) Tokens em credenciais (cabeçalho) — vinculadas na tela do n8n.
  for (const n of wf.nodes) {
    if (n.type === 'n8n-nodes-base.httpRequest') useCredentials(n);
    if (n.type === 'n8n-nodes-base.redis') n.credentials = { redis: 'Redis' };
  }
};
