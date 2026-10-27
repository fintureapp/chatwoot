// Ajustes dos fluxos de triagem (Triagem Parceiros e Suporte Clientes) para
// entender áudio. O Chatwoot transcreve o áudio em segundo plano
// (Finture::AudioTranscriptionService) e avisa com message_updated, trazendo no
// anexo `transcribed_text` e `transcription_status`. Aqui o fluxo:
//   1. aceita esse message_updated e usa a transcrição como texto da mensagem;
//   2. deduplica o áudio por 7 dias (o mesmo áudio pode gerar outros message_updated);
//   3. avisa o Haiku que o texto veio de áudio (pode ter erro; nunca inventar);
//   4. áudio que não deu para transcrever: pede para repetir/escrever; na 2ª vez
//      seguida, passa para um humano com nota explicando.
// Tudo por âncora de texto: funciona no fluxo publicado e também depois do
// ../n8n-modo-atendimento/mods.js (ordem indiferente).
const FLOWS = {
  FutuZQcHKnslRXG8: { etapaInicial: 'ramo' }, // Suporte Clientes (12 e 20)
  jIzoOMeCcpXSmSnG: { etapaInicial: 'tipo' }, // Triagem Parceiros (4)
};

const AUDIO_TTL = 604800; // 7 dias

function byName(wf, name) {
  const n = wf.nodes.find(x => x.name === name);
  if (!n) throw new Error('nó não encontrado: ' + name);
  return n;
}

function patch(str, from, to, label) {
  if (!str.includes(from)) throw new Error('âncora não encontrada (' + label + '): ' + from.slice(0, 80));
  if (str.includes(to)) throw new Error('ajuste já aplicado (' + label + ')');
  return str.replace(from, to);
}

const FILTRO_AUDIO = `// Áudio do cliente: chega por message_updated quando a transcrição termina
// (attachments[].transcription_status). Com transcrição, o texto vira o conteúdo
// da mensagem; sem (inaudível, longo demais, erro), segue com texto vazio e o
// Motor pede para repetir. O message_created do áudio (sem texto) continua de fora.
const _anexos = Array.isArray(body.attachments) ? body.attachments : [];
const _audio = _anexos.find(function (a) { return a && a.file_type === 'audio'; });
const _statusAudio = _audio && _audio.transcription_status ? String(_audio.transcription_status) : null;
const _semTexto = !(body.content && typeof body.content === 'string' && body.content.trim().length > 0);
const ehAudio = event === 'message_updated' && !!_audio && _semTexto && ['ok', 'unintelligible', 'too_long', 'failed'].indexOf(_statusAudio) !== -1;
if (ehAudio) {
  const _texto = _statusAudio === 'ok' ? String(_audio.transcribed_text || '').trim() : '';
  body.content = _texto;
  body.finture_audio = { status: _texto ? 'ok' : (_statusAudio === 'ok' ? 'unintelligible' : _statusAudio), attachmentId: _audio.id };
}
const hasContent = ehAudio || !_semTexto;
const eventoOk = event === 'message_created' || ehAudio;`;

const DEDUP = `// Áudio (message_updated com a transcrição): chave própria e longa, porque o mesmo
// áudio pode gerar outros message_updated depois.
const dedupKey = (body.finture_audio ? 'dedup:audio:' : 'dedup:msg:') + body.id;
const dedupTtl = body.finture_audio ? ${AUDIO_TTL} : 300;`;

const EXTRAIR_MENSAGEM = `let mensagem = (body.content || '').trim();
// Áudio respondendo ao menu ("um", "opção dois"): vira o número, como se digitado.
if (body.finture_audio && mensagem) {
  const _numeros = { um: '1', uma: '1', dois: '2', duas: '2', tres: '3', quatro: '4', cinco: '5', seis: '6', sete: '7', oito: '8' };
  const _falado = mensagem.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '').replace(/[.!?,;]/g, ' ').replace(/\\s+/g, ' ').trim();
  const _m = _falado.match(/^(?:(?:a )?opcao |(?:o )?numero |a |o )?(um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|[1-8])$/);
  if (_m) mensagem = _numeros[_m[1]] || _m[1];
}`;

const EXTRAIR_AUDIO = `const messageId = body.id;
// Áudio transcrito (Filtrar Evento): origem e situação seguem até o Motor e o Haiku.
const origemAudio = !!body.finture_audio;
const audioStatus = origemAudio ? body.finture_audio.status : null;`;

function motorAudio(etapaInicial) {
  return `
// Áudio que não deu para transcrever (inaudível, longo demais ou erro do motor):
// pede para mandar de novo ou escrever; na 2ª vez seguida, passa para um humano.
// Nunca tenta adivinhar o que foi dito.
if (dados.audioStatus && dados.audioStatus !== 'ok') {
  const _falhas = ((estado && estado.audioFalhas) || 0) + 1;
  if (_falhas >= 2) {
    const _prod = estado && estado.produto ? estado.produto : null;
    return [{ json: Object.assign({}, base, { acao: 'handoff', teamName: _prod ? PRODUTO_TEAM[_prod] : TEAM_DEFAULT, tipoDemanda: (estado && estado.tipoDemanda) || null, produto: _prod, descricao: (estado && estado.descricao) || 'Mandou áudio que não deu para transcrever (2 tentativas). Ouvir o áudio na conversa.', motivo: 'Áudio não transcrito', confirmacao: '' }) }];
  }
  const _msgAudio = dados.audioStatus === 'too_long'
    ? 'Seu áudio ficou um pouco longo pra eu ouvir por aqui. Pode mandar um áudio mais curto ou escrever em poucas palavras o que você precisa?'
    : 'Não consegui entender seu áudio. Pode mandar de novo ou escrever em poucas palavras o que você precisa?';
  const _novoEstado = Object.assign({ etapa: '${etapaInicial}', produto: null, descricao: null }, estado || {}, { audioFalhas: _falhas, updatedAt: now });
  return [{ json: Object.assign({}, base, { acao: 'perguntar', mensagemBot: _msgAudio, novoEstadoJson: JSON.stringify(_novoEstado) }) }];
}

if (pedeAtendente(m)) {`;
}

const HAIKU_AUDIO = `const _origemAudio = !!$('Extrair Dados Chatwoot').first().json.origemAudio;
const _notaAudio = _origemAudio ? 'ATENCAO: a mensagem abaixo veio de um AUDIO, transcrito automaticamente. Pode ter erros de transcricao (nomes, numeros, produtos): interprete pelo sentido. Se estiver confusa ou sem sentido, use acao "perguntar" e peca para confirmar por escrito. NUNCA invente o que foi dito.\\n' : '';
const userMsg = _notaAudio + `;

const HANDOFF_AUDIO = `const _viaAudio = !!$('Extrair Dados Chatwoot').first().json.origemAudio;
const PRODUTO_LABELS =`;

module.exports = function apply(wf) {
  const flow = FLOWS[wf.id];
  if (!flow) throw new Error('fluxo sem configuração de áudio: ' + wf.id);

  // 1) Filtro aceita o message_updated do áudio transcrito.
  const filtro = byName(wf, 'Filtrar Evento');
  let code = filtro.parameters.jsCode;
  code = patch(code, "const hasContent = body.content && typeof body.content === 'string' && body.content.trim().length > 0;", FILTRO_AUDIO, 'filtro-conteudo');
  code = patch(code, "if (event !== 'message_created' || ", 'if (!eventoOk || ', 'filtro-evento');
  filtro.parameters.jsCode = code;

  // 2) Deduplicação própria do áudio (7 dias).
  const dedup = byName(wf, 'Montar Dedup Key');
  code = patch(dedup.parameters.jsCode, "const dedupKey = 'dedup:msg:' + body.id;", DEDUP, 'dedup-chave');
  dedup.parameters.jsCode = patch(code, 'Object.assign({}, body, { dedupKey })', 'Object.assign({}, body, { dedupKey, dedupTtl })', 'dedup-retorno');
  const redis = byName(wf, 'Redis Dedup (incr)');
  if (redis.parameters.ttl !== 300) throw new Error('ttl inesperado no Redis Dedup: ' + redis.parameters.ttl);
  redis.parameters.ttl = '={{ $json.dedupTtl || 300 }}';

  // 3) Origem/situação do áudio + número falado ao menu.
  const extrair = byName(wf, 'Extrair Dados Chatwoot');
  code = patch(extrair.parameters.jsCode, "const mensagem = (body.content || '').trim();", EXTRAIR_MENSAGEM, 'extrair-mensagem');
  code = patch(code, 'const messageId = body.id;', EXTRAIR_AUDIO, 'extrair-audio');
  extrair.parameters.jsCode = patch(code, 'messageId, chave:', 'messageId, origemAudio, audioStatus, chave:', 'extrair-retorno');

  // 4) Áudio sem transcrição: pedir de novo; 2ª vez = humano.
  const motor = byName(wf, 'Motor Triagem');
  motor.parameters.jsCode = patch(motor.parameters.jsCode, '\nif (pedeAtendente(m)) {', motorAudio(flow.etapaInicial), 'motor');

  // 5) Haiku sabe que o texto veio de áudio.
  const haiku = byName(wf, 'Montar Body Haiku');
  haiku.parameters.jsCode = patch(haiku.parameters.jsCode, 'const userMsg = ', HAIKU_AUDIO, 'haiku');

  // 6) Nota interna do handoff avisa que a demanda veio por áudio.
  const prep = byName(wf, 'Preparar Handoff');
  code = patch(prep.parameters.jsCode, 'const PRODUTO_LABELS =', HANDOFF_AUDIO, 'handoff-origem');
  prep.parameters.jsCode = patch(code, 'const notaPrivada =\n',
    "const notaPrivada = (_viaAudio ? '[Mensagem recebida por áudio, com transcrição automática. Confira o áudio original na conversa.]\\n\\n' : '') +\n",
    'handoff-nota');
};
