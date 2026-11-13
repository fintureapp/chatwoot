# Central de Demandas: Chatwoot → HUB Finture

Conversas das caixas **operacionais** que entram em atendimento humano viram demandas na Central de Demandas do HUB Finture (repo `Dash-Inteligente-Finture`), já atribuídas ao agente responsável, com o contexto (resumo da IA) e o plano de ação do card do Kanban. O Chatwoot é a fonte da verdade do atendimento; o HUB guarda uma cópia para a Central. Nada volta do HUB para o Chatwoot nesta fase.

O contrato completo da API (payload, respostas, idempotência) está no HUB, em `API_DEMANDAS.md`.

## Como funciona

```
Conversa muda (responsável, etapa, status, time, plano de ação, resumo)
  → conversation_updated (assíncrono)
  → Finture::DemandaListener: a mudança interessa? caixa é operacional? integração ligada?
  → Finture::DemandaSyncJob (fila low, 6 tentativas em erro passageiro)
  → Finture::DemandaSyncService: relê a conversa
      sem linha em finture_demanda_syncs e (etapa != em_atendimento ou sem responsável) → nada
      senão → POST {FINTURE_HUB_BASE_URL}/api/v1/demandas/ingest (X-Ingest-Secret)
  → HUB faz UPSERT por external_id (chatwoot:<account_id>:<display_id>)
```

- **Quando a demanda nasce:** no primeiro momento em que a conversa está na etapa `em_atendimento` (slug; o nome exibido pode mudar) **e** tem responsável. Não importa a ordem: o listener enfileira nos dois eventos e o service relê o estado.
- **Depois de criada:** qualquer mudança de responsável, etapa (inclusive sair de Em atendimento), status, time, `sdr_next_action`, `sdr_resumo_ia`, `sdr_resumo` ou `produto_interesse` reenvia a demanda como `updated`. Mesmo payload não é reenviado (hash em `last_payload_hash`).
- **Contexto:** `sdr_resumo_ia` é gravado pelo fluxo n8n "Finture - Kanban SDR: Mover Cards (v2)" no handoff (resumo que hoje só vai na nota privada). `sdr_resumo` chega no resolve, como `resumo_final`. Sem o atributo a demanda nasce com `contexto` vazio, nunca deixa de nascer.
- **Ciclo de vida:** o ingest não fecha nem reabre demanda; o HUB recebe `status_origem` e `etapa` e decide depois (fase 2).
- **Loop de eventos:** o service nunca escreve em `custom_attributes`. O estado fica em `finture_demanda_syncs`, que não dispara `conversation_updated`.

## Variáveis de ambiente

| Variável | Para quê |
|---|---|
| `FINTURE_HUB_BASE_URL` | Base do HUB, ex. `https://finture-api.azurewebsites.net` |
| `FINTURE_HUB_INGEST_SECRET` | Mesmo valor de `DEMANDAS_INGEST_SECRET` no HUB (`openssl rand -hex 32`) |

Vazio = integração desligada (o listener sai antes de enfileirar). Nos Container Apps, configurar nas revisões **rails e sidekiq**: o envio roda no Sidekiq. Em desenvolvimento, HUB local em `http://localhost:8001` funciona direto; staging exige o host em `LOCAL_EGRESS_ALLOWLIST` (trava de `config/initializers/000_finture_local_isolation.rb`).

## Tabela `finture_demanda_syncs`

| Coluna | Significado |
|---|---|
| `conversation_id`, `external_id` | 1 linha por conversa; `external_id` = `chatwoot:<account_id>:<display_id>` |
| `hub_demanda_id` | id devolvido pelo HUB no primeiro envio aceito |
| `status` | `pending` (criada), `synced` (último envio aceito), `retrying` (erro passageiro, job vai tentar), `failed` (HUB recusou ou tentativas esgotadas) |
| `last_event` | `created` ou `updated` |
| `last_payload_hash` | SHA-256 do último payload aceito, sem `ocorrido_em`/`evento` |
| `last_sent_at`, `last_error`, `attempts` | diagnóstico |

## Operação

- **Ver pendências:** `Finture::DemandaSync.where(status: %w[retrying failed]).pluck(:external_id, :status, :last_error)`.
- **Reprocessar uma conversa** (console): `Finture::DemandaSyncJob.perform_later(conversation.id, Time.current.iso8601)`. O service relê tudo e reenvia; o HUB aceita repetição.
- **Reenviar tudo que falhou:** `Finture::DemandaSync.where(status: 'failed').find_each { |s| Finture::DemandaSyncJob.perform_later(s.conversation_id, Time.current.iso8601) }`.
- **Forçar o primeiro envio de conversas antigas** já em Em atendimento com responsável: enfileirar o job para cada uma; sem linha de sync, o service cria se a conversa for elegível.

## Ordem de deploy

1. HUB (staging, depois produção) com `DEMANDAS_INGEST_SECRET`; a tabela `demandas` é criada no boot.
2. Chatwoot: `db:migrate` (`finture_demanda_syncs`) e código. Com as ENVs vazias nada acontece, então o código pode subir antes da configuração.
3. Configurar `FINTURE_HUB_BASE_URL` e `FINTURE_HUB_INGEST_SECRET` (rails e sidekiq) apontando primeiro para a staging do HUB; validar; depois produção.
4. n8n: no fluxo "Finture - Kanban SDR: Mover Cards (v2)" (`44iWAbkAg1A5xFy8`), nó que monta os atributos após o "Parser Claude", acrescentar `attrs.sdr_resumo_ia = resumo;` e publicar.

## Validação ponta a ponta

1. Em caixa operacional, mover um card para Em atendimento sem responsável: nada chega ao HUB.
2. Atribuir um agente cujo e-mail existe no HUB: `GET /api/v1/demandas?minhas=1` com o JWT dele mostra a demanda (`responsavel.vinculado: true`).
3. Gravar `sdr_next_action` (n8n ou API): `plano_acao` atualizado no HUB.
4. Resolver a conversa: `status_origem: resolved`; a demanda continua `aberta` (fase 2 decide).
5. Agente sem cadastro no HUB: demanda chega com `responsavel_vinculado: false`.
6. HUB fora do ar: linha em `retrying`, sucesso quando voltar. Segredo errado: `failed`, sem novas tentativas.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `app/listeners/finture/demanda_listener.rb` | Filtra o `conversation_updated` e enfileira |
| `app/jobs/finture/demanda_sync_job.rb` | Retentativas e marcação de `failed` |
| `app/services/finture/demanda_sync_service.rb` | Regra de elegibilidade, payload, estado |
| `app/services/finture/hub_client.rb` | HTTP com o HUB |
| `app/models/finture/demanda_sync.rb` | Estado do envio por conversa |
| `db/migrate/20261112120000_create_finture_demanda_syncs.rb` | Tabela |
