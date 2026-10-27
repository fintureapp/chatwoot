// Aplica ajustes (mods) ao JSON de um fluxo (get_workflow_details do MCP do n8n)
// e gera o código do n8n Workflow SDK para update_workflow, igual ao
// ../n8n-modo-atendimento/gen.js, mas aceitando vários arquivos de ajuste em ordem.
//
// Uso: node aplicar.js <fluxo.json> <saida.js> <mods1.js> [mods2.js ...]
//   ex.: node aplicar.js suporte.json suporte.workflow.js ../n8n-modo-atendimento/mods.js mods-audio.js
// Com --json no lugar de <saida.js>, imprime o fluxo ajustado em JSON (para conferir).
const fs = require('fs');
const path = require('path');

const [, , inFile, outFile, ...modFiles] = process.argv;
if (!inFile || !outFile || modFiles.length === 0) {
  console.error('uso: node aplicar.js <fluxo.json> <saida.js|--json> <mods.js> [...]');
  process.exit(1);
}

const data = JSON.parse(fs.readFileSync(inFile, 'utf8'));
const src = data.workflow || data;
const wf = { id: src.id, name: src.name, nodes: JSON.parse(JSON.stringify(src.nodes)), connections: JSON.parse(JSON.stringify(src.connections)) };
for (const m of modFiles) require(path.resolve(process.cwd(), m))(wf);

if (outFile === '--json') {
  process.stdout.write(JSON.stringify(wf, null, 2));
  process.exit(0);
}

const CRED = '__CRED__';
const varName = {};
wf.nodes.forEach((n, i) => { varName[n.name] = 'n' + i; });

const out = ["import { workflow, node, trigger, newCredential } from '@n8n/workflow-sdk';", ''];
for (const n of wf.nodes) {
  const isTrigger = n.type === 'n8n-nodes-base.webhook';
  const config = { name: n.name, parameters: n.parameters || {}, position: n.position };
  for (const k of ['onError', 'retryOnFail', 'alwaysOutputData', 'executeOnce', 'webhookId']) if (n[k]) config[k] = n[k];
  if (n.credentials) {
    config.credentials = Object.fromEntries(Object.entries(n.credentials).map(([k, v]) => [k, CRED + (typeof v === 'string' ? v : v.name) + CRED]));
  }
  let cfg = JSON.stringify(config);
  cfg = cfg.replace(new RegExp('"' + CRED + '([^"]*)' + CRED + '"', 'g'), (_, name) => 'newCredential(' + JSON.stringify(name) + ')');
  out.push(`const ${varName[n.name]} = ${isTrigger ? 'trigger' : 'node'}({ type: ${JSON.stringify(n.type)}, version: ${n.typeVersion}, config: ${cfg}, output: [{}] });`);
}
out.push('');
const start = wf.nodes.find(n => n.type === 'n8n-nodes-base.webhook');
let chain = `export default workflow(${JSON.stringify(wf.id)}, ${JSON.stringify(wf.name)})\n  .add(${varName[start.name]})`;
for (const [srcName, conn] of Object.entries(wf.connections)) {
  (conn.main || []).forEach((targets, idx) => {
    (targets || []).forEach(t => {
      chain += `\n  .add(${varName[srcName]}.output(${idx}).to(${varName[t.node]}))`;
    });
  });
}
out.push(chain + ';');
fs.writeFileSync(outFile, out.join('\n'));
console.log('ok', wf.nodes.length, 'nós ->', outFile, fs.statSync(outFile).size, 'bytes');
