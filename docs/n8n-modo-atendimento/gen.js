// Gera código do n8n Workflow SDK a partir do JSON de um workflow (get_workflow_details),
// opcionalmente aplicando transformações (mods.js). Uso: node gen.js <in.json> <out.js> [mods]
const fs = require('fs');
const path = require('path');

const [, , inFile, outFile, withMods] = process.argv;
const data = JSON.parse(fs.readFileSync(inFile, 'utf8'));
let wf = data.workflow;
wf = { id: wf.id, name: wf.name, nodes: JSON.parse(JSON.stringify(wf.nodes)), connections: JSON.parse(JSON.stringify(wf.connections)) };

if (withMods) require(path.resolve(__dirname, 'mods.js'))(wf);

const CRED = '__CRED__';
const varName = {};
wf.nodes.forEach((n, i) => { varName[n.name] = 'n' + i; });

const out = ["import { workflow, node, trigger, newCredential } from '@n8n/workflow-sdk';", ''];
for (const n of wf.nodes) {
  const isTrigger = n.type === 'n8n-nodes-base.webhook';
  const config = { name: n.name, parameters: n.parameters || {}, position: n.position };
  if (n.onError) config.onError = n.onError;
  if (n.retryOnFail) config.retryOnFail = n.retryOnFail;
  if (n.alwaysOutputData) config.alwaysOutputData = n.alwaysOutputData;
  if (n.executeOnce) config.executeOnce = n.executeOnce;
  if (n.webhookId) config.webhookId = n.webhookId;
  if (n.credentials) config.credentials = Object.fromEntries(Object.entries(n.credentials).map(([k, v]) => [k, CRED + v + CRED]));
  let cfg = JSON.stringify(config);
  cfg = cfg.replace(new RegExp('"' + CRED + '([^"]*)' + CRED + '"', 'g'), (_, name) => 'newCredential(' + JSON.stringify(name) + ')');
  out.push(`const ${varName[n.name]} = ${isTrigger ? 'trigger' : 'node'}({ type: ${JSON.stringify(n.type)}, version: ${n.typeVersion}, config: ${cfg}, output: [{}] });`);
}
out.push('');
const start = wf.nodes.find(n => n.type === 'n8n-nodes-base.webhook');
let chain = `export default workflow(${JSON.stringify(wf.id)}, ${JSON.stringify(wf.name)})\n  .add(${varName[start.name]})`;
for (const [src, conn] of Object.entries(wf.connections)) {
  (conn.main || []).forEach((targets, idx) => {
    (targets || []).forEach(t => {
      chain += `\n  .add(${varName[src]}.output(${idx}).to(${varName[t.node]}))`;
    });
  });
}
out.push(chain + ';');
fs.writeFileSync(outFile, out.join('\n'));
console.log('ok', wf.nodes.length, 'nodes ->', outFile, fs.statSync(outFile).size, 'bytes');
