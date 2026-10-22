# Fluxos n8n: modo de atendimento (Assumir / Devolver à IA)

Ajustes dos fluxos de triagem para o modo de atendimento autoritativo do Chatwoot (commit `10e20e6f7`, branch `atualizacoes-v2-chatwoot`).

**Situação (22/10/2026):** os dois fluxos já estão **publicados** no n8n com estes ajustes e com as credenciais vinculadas. Eles funcionam com o Chatwoot atual de produção porque caem no comportamento antigo onde o servidor novo não responde (sem `finture_attendance`, sem flag de revisão; `bot_handoff` 404 → caminho antigo). Quando o Chatwoot com o commit acima subir, as travas novas passam a valer sozinhas. Falta só ligar "Atendimento com IA" nas caixas 4, 12 e 20.

| Fluxo | ID n8n | Caixas | Arquivo |
|---|---|---|---|
| GPT Seguros — Triagem Parceiros (v1) | `jIzoOMeCcpXSmSnG` | 4 | `triagem-parceiros.workflow.js` |
| GPT Seguros — Suporte Clientes (v1) | `FutuZQcHKnslRXG8` | 12 e 20 | `suporte-clientes.workflow.js` |

Os `.workflow.js` são código do n8n Workflow SDK, prontos para `update_workflow` (MCP do n8n). Eles foram gerados em 22/10/2026 a partir da versão publicada nessa data.

## O que muda (igual nos dois fluxos)

1. **Consulta de estado falhou = bot quieto.** O "Avaliar Estado Atendimento" usa `finture_attendance` quando o Chatwoot manda. Sem ele, vale a regra antiga (atributo + etiqueta).
2. **Revisão no envio.** O "Enviar Menu Chatwoot" manda `content_attributes.finture_bot_revision`. Se o Chatwoot recusar (alguém assumiu), o fluxo vai para "Responder OK (Envio Recusado)" e não reabre a conversa.
3. **Handoff pelo endpoint novo.** O nó "Registrar Handoff (Chatwoot)" chama `POST .../finture_attendance/bot_handoff`, enviando a triagem.
   - **2xx:** segue o fluxo, e a confirmação ao cliente leva a revisão nova.
   - **409:** um humano já assumiu. O fluxo para, sem confirmação.
   - **Outro erro:** cai no caminho antigo (custom_attributes + labels).
4. **Retomada.** Quando o atendente usa "Devolver à IA" e não há estado no Redis, o fluxo não reapresenta o menu. Ele segue pelo Haiku com o motivo e as pendências.
5. **Tokens em credenciais.** Nenhum token fica no fluxo.

## Como reaplicar (se os fluxos precisarem ser refeitos)

1. Criar no n8n 3 credenciais **Header Auth**, com estes nomes exatos:
   - `Chatwoot API - leitura (n8n)`: cabeçalho `api_access_token`, valor = o token do nó "GET Estado Conversa (Guard)" do fluxo publicado.
   - `Chatwoot API - Bia (envio)`: cabeçalho `api_access_token`, valor = o token do nó "Enviar Menu Chatwoot".
   - `Anthropic API (x-api-key)`: cabeçalho `x-api-key`, valor = uma chave nova da Anthropic. A atual está em texto puro no fluxo: revogar.
2. **Se o fluxo publicado mudou desde 22/10**, regenerar em vez de usar o `.workflow.js` salvo, para não desfazer alterações de outras pessoas:
   - salvar o JSON do `get_workflow_details` em `fluxo.json`;
   - rodar `node gen.js fluxo.json saida.js mods`;
   - se algum ajuste não se encaixar mais no fluxo, o `mods.js` avisa qual âncora não foi encontrada.
3. `update_workflow` com o código. Isso cria só um **rascunho**; a versão publicada não muda. O Redis é vinculado sozinho.
4. No editor do n8n, vincular as credenciais nos 14 nós HTTP de cada fluxo.
5. Testar pelo webhook de teste e depois `publish_workflow`.
6. No Chatwoot, ligar "Atendimento com IA" nas caixas 4, 12 e 20 (Configurações → Caixa).

## Arquivos

- `gen.js`: converte o JSON de um fluxo (get_workflow_details) em código do SDK. Com `mods`, aplica o `mods.js`.
- `mods.js`: as transformações acima, aplicadas por âncora de texto.
