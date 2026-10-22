// Simula os nós de código dos fluxos de triagem já ajustados, com eventos de
// áudio, sem precisar do n8n. Rodar depois de regenerar, antes do update_workflow.
//   node simular.js <suporte.json> <parceiros.json> [mods extras aplicados antes, ex.: ../n8n-modo-atendimento/mods.js]
// Os .json são a saída do get_workflow_details (MCP do n8n) dos fluxos publicados.
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const [, , suporteFile, parceirosFile, ...extras] = process.argv;
if (!suporteFile || !parceirosFile) {
  console.error('uso: node simular.js <suporte.json> <parceiros.json> [mods extras...]');
  process.exit(1);
}
const modsAudio = require(path.join(__dirname, 'mods-audio.js'));
const modsExtras = extras.map(m => require(path.resolve(process.cwd(), m)));

function load(file) {
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  const w = data.workflow || data;
  return { id: w.id, name: w.name, nodes: JSON.parse(JSON.stringify(w.nodes)), connections: JSON.parse(JSON.stringify(w.connections)) };
}

function node(wf, name) { return wf.nodes.find(n => n.name === name); }

// Roda um Code node: $input = item atual; $('Nó') = saídas já calculadas.
function run(wf, name, input, outputs) {
  const code = node(wf, name).parameters.jsCode;
  const $ = n => {
    if (!(n in outputs)) throw new Error('sem saída simulada para ' + n);
    const v = outputs[n];
    return { first: () => ({ json: v }), item: { json: v } };
  };
  const $input = { first: () => ({ json: input }) };
  const fn = new Function('$', '$input', code);
  const res = fn($, $input);
  return res && res[0] ? res[0].json : null;
}

function evento(overrides) {
  return Object.assign({
    event: 'message_updated', id: 777, message_type: 'incoming', content: null,
    sender: { type: 'contact', name: 'Maria', phone_number: '+5511999990000' },
    account: { id: 1 },
    conversation: { id: 55, assignee_id: null, status: 'open', contact_inbox: { source_id: '5511999990000' }, meta: { sender: { id: 9, custom_attributes: {} } } },
    attachments: [{ id: 31, file_type: 'audio', transcribed_text: 'Oi, quero falar sobre consórcio', transcription_status: 'ok' }],
  }, overrides);
}

function cenario(wf, webhookName, inbox, body, estadoRaw) {
  body.inbox = { id: inbox };
  const out = {};
  out[webhookName] = { body };
  const filtrado = run(wf, 'Filtrar Evento', { body }, out);
  if (!filtrado) return { filtrado: null };
  out['Filtrar Evento'] = filtrado;
  const dedup = run(wf, 'Montar Dedup Key', filtrado, out);
  const dados = run(wf, 'Extrair Dados Chatwoot', dedup, out);
  out['Extrair Dados Chatwoot'] = dados;
  out['Avaliar Estado Atendimento'] = Object.assign({}, dados, { emAtendimentoHumano: false, labelsAtuais: [], customAttrsAtuais: {}, revisao: 3, retomada: null });
  out['Buscar Estado Triagem'] = { estadoRaw: estadoRaw || null };
  out['Buscar Historico Contato'] = { payload: [] };
  const motor = run(wf, 'Motor Triagem', dados, out);
  out['Motor Triagem'] = motor;
  let haiku = null;
  if (motor.acao === 'interpretar') haiku = run(wf, 'Montar Body Haiku', motor, out);
  let handoff = null;
  if (motor.acao === 'handoff') handoff = run(wf, 'Preparar Handoff', motor, out);
  return { filtrado, dedup, dados, motor, haiku, handoff };
}

const FLUXOS = [
  { file: suporteFile, webhook: 'Webhook Chatwoot Suporte', inbox: 20, etapa: 'ramo' },
  { file: parceirosFile, webhook: 'Webhook Chatwoot Triagem', inbox: 4, etapa: 'tipo' },
];

const combos = modsExtras.length ? [['extras', 'audio'], ['audio', 'extras']] : [['audio']];
for (const combo of combos) {
  for (const f of FLUXOS) {
    const wf = load(f.file);
    for (const m of combo) (m === 'audio' ? [modsAudio] : modsExtras).forEach(fn => fn(wf));
    const tag = path.basename(f.file) + ' [' + combo.join('+') + ']';

    // Sintaxe de todos os Code nodes.
    for (const n of wf.nodes.filter(x => x.type === 'n8n-nodes-base.code')) new Function('$', '$input', n.parameters.jsCode);
    assert.strictEqual(node(wf, 'Redis Dedup (incr)').parameters.ttl, '={{ $json.dedupTtl || 300 }}');

    // 1) Áudio transcrito: vira texto e vai para o Haiku com a nota de áudio.
    let r = cenario(wf, f.webhook, f.inbox, evento({}));
    assert.ok(r.filtrado, tag + ': áudio ok deveria passar no filtro');
    assert.strictEqual(r.dedup.dedupKey, 'dedup:audio:777');
    assert.strictEqual(r.dedup.dedupTtl, 604800);
    assert.strictEqual(r.dados.mensagem, 'Oi, quero falar sobre consórcio');
    assert.strictEqual(r.dados.origemAudio, true);
    assert.strictEqual(r.motor.acao, 'interpretar', tag + ': ' + r.motor.acao);
    assert.ok(r.haiku.claudeBody.messages[0].content.startsWith('ATENCAO: a mensagem abaixo veio de um AUDIO'), tag);

    // 2) message_created do áudio (sem texto) continua fora.
    r = cenario(wf, f.webhook, f.inbox, evento({ event: 'message_created', attachments: [{ id: 31, file_type: 'audio', transcribed_text: '', transcription_status: null }] }));
    assert.strictEqual(r.filtrado, null, tag + ': message_created de áudio deveria ser ignorado');

    // 3) message_updated de áudio ainda sem status (ex.: broadcast do anexo) fica fora.
    r = cenario(wf, f.webhook, f.inbox, evento({ attachments: [{ id: 31, file_type: 'audio', transcribed_text: '' }] }));
    assert.strictEqual(r.filtrado, null, tag + ': update sem status deveria ser ignorado');

    // 4) message_updated de texto (edição etc.) continua fora.
    r = cenario(wf, f.webhook, f.inbox, evento({ content: 'oi', attachments: [] }));
    assert.strictEqual(r.filtrado, null, tag + ': update de texto deveria ser ignorado');

    // 5) Texto normal segue igual (dedup curto, sem nota de áudio).
    r = cenario(wf, f.webhook, f.inbox, evento({ event: 'message_created', content: 'quero cotar consórcio', attachments: [] }));
    assert.strictEqual(r.dedup.dedupKey, 'dedup:msg:777');
    assert.strictEqual(r.dedup.dedupTtl, 300);
    assert.strictEqual(r.dados.origemAudio, false);
    if (r.haiku) assert.ok(!r.haiku.claudeBody.messages[0].content.startsWith('ATENCAO'), tag);

    // 6) Áudio inaudível: 1ª vez pede de novo, guardando a contagem.
    r = cenario(wf, f.webhook, f.inbox, evento({ attachments: [{ id: 31, file_type: 'audio', transcribed_text: '', transcription_status: 'unintelligible' }] }));
    assert.strictEqual(r.dados.audioStatus, 'unintelligible');
    assert.strictEqual(r.motor.acao, 'perguntar');
    assert.ok(/Não consegui entender seu áudio/.test(r.motor.mensagemBot));
    const est = JSON.parse(r.motor.novoEstadoJson);
    assert.strictEqual(est.audioFalhas, 1);
    assert.strictEqual(est.etapa, f.etapa);

    // 7) 2ª falha seguida: humano, com nota avisando que veio por áudio.
    r = cenario(wf, f.webhook, f.inbox, evento({ attachments: [{ id: 31, file_type: 'audio', transcription_status: 'failed' }] }),
      JSON.stringify(Object.assign(est, { updatedAt: new Date().toISOString() })));
    assert.strictEqual(r.motor.acao, 'handoff');
    assert.ok(/Áudio não transcrito/.test(r.motor.motivo));
    assert.ok(r.handoff.notaPrivada.startsWith('[Mensagem recebida por áudio'), tag);

    // 8) Áudio longo: mensagem própria.
    r = cenario(wf, f.webhook, f.inbox, evento({ attachments: [{ id: 31, file_type: 'audio', transcription_status: 'too_long' }] }));
    assert.ok(/longo/.test(r.motor.mensagemBot));

    // 9) "ok" sem texto é tratado como inaudível (nunca segue vazio para a IA).
    r = cenario(wf, f.webhook, f.inbox, evento({ attachments: [{ id: 31, file_type: 'audio', transcribed_text: '  ', transcription_status: 'ok' }] }));
    assert.strictEqual(r.dados.audioStatus, 'unintelligible');

    // 10) Número falado ao menu vira dígito.
    for (const [falado, esperado] of [['Um.', '1'], ['Opção dois!', '2'], ['três', '3'], ['O número 4', '4']]) {
      r = cenario(wf, f.webhook, f.inbox, evento({ attachments: [{ id: 31, file_type: 'audio', transcribed_text: falado, transcription_status: 'ok' }] }));
      assert.strictEqual(r.dados.mensagem, esperado, tag + ': ' + falado);
    }
    console.log('ok', tag);
  }
}

// Aplicar duas vezes acusa (evita ajuste duplicado num fluxo já ajustado).
const wf2 = load(suporteFile);
modsAudio(wf2);
assert.throws(() => modsAudio(wf2));
console.log('ok reaplicar acusa');
