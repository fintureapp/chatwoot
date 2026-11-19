# Central de Demandas: Chatwoot → HUB Finture

Conversas das caixas **operacionais** que entram em atendimento humano viram demandas na Central de Demandas do HUB Finture (repo `Dash-Inteligente-Finture`), já atribuídas ao agente responsável, com o contexto (resumo da IA) e o plano de ação do card do Kanban. O Chatwoot é a fonte da verdade do atendimento; o HUB guarda uma cópia para a Central. Nada volta do HUB para o Chatwoot.

O contrato completo da API (payload, respostas, idempotência) está no HUB, em `API_DEMANDAS.md`. O HUB aceita `payload_version` 1 e 2.

## Como funciona

```
Conversa muda (responsável, etapa, status, time, plano de ação, resumo)
  → conversation_updated
  → Finture::DemandaListener (SÍNCRONO, logo após o commit):
      a mudança interessa? caixa é operacional? integração ligada?
      a conversa acabou de ficar elegível? → cria a linha com elegivel_em = horário do evento
      autor = usuário do painel que fez a mudança (ou nenhum)
  → Finture::DemandaSyncJob (fila low, 6 tentativas em erro passageiro)
  → Finture::DemandaSyncService: relê a conversa
      sem linha em finture_demanda_syncs e (etapa != em_atendimento ou sem responsável) → nada
      senão → POST {FINTURE_HUB_BASE_URL}/api/v1/demandas/ingest (X-Ingest-Secret)
  → HUB faz UPSERT por external_id (chatwoot:<account_id>:<display_id>)
```

- **Quando a demanda nasce:** no primeiro momento em que a conversa está na etapa `em_atendimento` (slug; o nome exibido pode mudar) **e** tem responsável. Não importa a ordem: o listener enfileira nos dois eventos e o service relê o estado.
- **Depois de criada:** qualquer mudança de responsável, etapa (inclusive sair de Em atendimento), status, time, `sdr_next_action`, `sdr_resumo_ia`, `sdr_resumo` ou `produto_interesse` reenvia a demanda como `updated`. Conteúdo igual ao último **aplicado** não é reenviado (hash em `last_payload_hash`).
- **Por que o listener é síncrono:** é o único ponto que ainda enxerga quem fez a mudança (`Current`) e o estado antes/depois dela. Ele só filtra, grava `elegivel_em` quando é o caso e enfileira; o HTTP continua no job. Erros dentro dele são capturados e logados (não afetam a requisição nem os outros listeners).
- **Contexto:** `sdr_resumo_ia` é gravado pelo fluxo n8n do Kanban SDR no handoff. `sdr_resumo` chega no resolve, como `resumo_final`. Sem o atributo a demanda nasce com `contexto` vazio, nunca deixa de nascer.
- **Loop de eventos:** o service nunca escreve em `custom_attributes`. O estado fica em `finture_demanda_syncs`, que não dispara `conversation_updated`.

## Payload v2

O v2 é o v1 com quatro campos a mais. `FINTURE_HUB_PAYLOAD_VERSION=1` volta a enviar o v1 exato (sem trocar a imagem), para um HUB que ainda não aceita o v2.

| Campo | Origem | Quando vai |
|---|---|---|
| `conversa_criada_em` | `conversations.created_at` | sempre (informativo: o HUB não usa como início do atendimento) |
| `elegivel_em` | `finture_demanda_syncs.elegivel_em` | só quando registrado; **omitido** se desconhecido, nunca aproximado |
| `sequencia` | `finture_demanda_syncs.sequencia` | sempre; inteiro monotônico por conversa |
| `autor` `{email, nome}` | usuário que fez a mudança pelo painel | só com usuário identificável; **omitido** para automação, API e sistema |

### `elegivel_em`

- É gravado pelo listener **no instante do evento** em que a conversa passou de não elegível para elegível (caixa operacional + `em_atendimento` + responsável), comparando o estado antes e depois daquela mudança. A linha de `finture_demanda_syncs` nasce nesse momento, já com ele.
- É **fixo por demanda**: o mesmo em todos os eventos, retentativas, reprocessamentos e reconciliações. Se a conversa sai de Em atendimento e volta, o valor não muda (o HUB só usa `elegivel_em` para o início do ciclo 1).
- Fica **desconhecido** (campo omitido) quando o instante não foi visto: demandas criadas pelo v1, conversas que já eram elegíveis quando a integração foi ligada, ou se o job criar a linha antes do listener (corrida de milissegundos). Nunca é preenchido depois com outra data.

### `sequencia`

- Atribuída no envio, dentro do lock da linha (`with_lock`), e gravada antes do POST.
- Envio novo = número seguinte, inclusive duas mudanças no mesmo segundo (o `ocorrido_em` tem resolução de segundo; a sequência desempata).
- A **retentativa do mesmo envio** (corpo idêntico; o job repete com os mesmos argumentos) reaproveita o número (`attempt_hash`): o corpo sai byte a byte igual, e o HUB responde `duplicado` se já o tinha gravado. Assim um timeout depois de o HUB gravar não vira evento duplicado.

### `autor`

- Vem de `Current.user`, lido pelo listener síncrono: o usuário logado no painel (inclusive ações em lote e macros que ele executou).
- Não vai quando a mudança veio de automação ou sistema (`Current.executed_by`: regra de automação, atribuição automática, assistente, contato reabrindo), de **token de API** (`Current.api_access_token_auth`, marcado em `AccessTokenAuthHelper`; é como o n8n chama o Chatwoot, mesmo com o token de um agente), de bot, ou de job sem usuário.
- Nunca é o responsável deduzido nem o contato.

### `ocorrido_em`

É o horário do evento no Chatwoot (`event.timestamp`, gravado no despacho, logo após o commit da mudança), em UTC e com resolução de segundo. Cai no **horário do envio** só quando o job roda sem horário:

- reprocessamento manual pelo console (`Finture::DemandaSyncJob.perform_now(conversation.id)`); nesse caso cada retentativa usa um novo horário;
- reconciliação, de propósito: o reenvio é um evento novo com a data corrigida (horário do servidor quando a reconciliação roda).

## Respostas do HUB

| Resposta | Linha fica | `last_payload_hash` |
|---|---|---|
| 201/200, `motivo: null` (aplicado) | `synced` | gravado |
| 200, `motivo: "duplicado"` (o HUB já tinha esse evento) | `synced` | gravado |
| 200, `ignorado: true`, `motivo: "futuro"` ou `"atrasado"` | `divergent`, `recovery_state: pending`, `hub_motivo`, `rejected_at` | **não** gravado |
| 429/5xx/rede | `retrying` (o job tenta de novo) | não muda |
| outros 4xx | `failed` | não muda |

- **`futuro`** (`ocorrido_em` além de `recebido_em` + 5 min no HUB, relógio adiantado): não é sucesso. Como o hash não é gravado, o próximo envio sai mesmo com o conteúdo igual. No 1º evento da conversa o HUB responde `demanda: null`: a linha continua sem `hub_demanda_id` e o próximo envio sai de novo como `created`. O caso fica consultável no Chat pela linha (conversa, `hub_motivo`, `recovery_state`, `rejected_at`), mesmo sem demanda no HUB.
- **Recuperação:** o primeiro envio aplicado depois disso (próxima mudança ou reconciliação) deixa `synced`, `recovery_state: recovered` e `recovered_at`. Se a tentativa seguinte falhar de vez (4xx ou tentativas esgotadas), `recovery_state: failed`, e a reconciliação tenta de novo.
- **Limite conhecido:** se um envio rejeitado como `futuro` for repetido byte a byte (retentativa depois de um timeout), o HUB responde `duplicado` e a linha fica `synced` sem o evento aplicado. Reenviar a conversa com `reconciliar_conversa` (abaixo) resolve. O mesmo vale para rejeições `futuro` recebidas enquanto o v1 estava no ar: o v1 tratava qualquer 2xx como sucesso, então essas linhas estão `synced`; o HUB registra o `external_id` no log (WARNING), e a recuperação é por conversa.

## Reconciliação

`Finture::DemandaReconcileService` reenvia o **estado atual** das conversas cujo envio não terminou aplicado, sem ninguém editar a conversa. Cada reenvio é um evento novo: `ocorrido_em` = horário do servidor na execução (outro `event_key` no HUB) e a próxima `sequencia`; sem `autor`.

Candidatas, em ordem de id:

- `failed` e `divergent`;
- `pending`/`retrying` parados há mais de 1 hora (job perdido);
- com `DRIFT=1`: `synced` cujo conteúdo atual difere do último aplicado (mudança que não gerou envio). Percorre todas as linhas `synced` e monta o payload de cada uma; rodar fora do horário de pico.

Idempotência: o job repete com os mesmos argumentos (mesmo corpo e sequência; o HUB deduplica) e, se a conversa ficou `synced` com o mesmo conteúdo antes de o job rodar, não envia nada. Rodar de novo depois de tudo aplicado não seleciona nada.

```bash
bundle exec rake finture:demandas:pendencias                       # o que não está aplicado + recuperações em aberto
DRY_RUN=1 bundle exec rake "finture:demandas:reconciliar[50]"      # só lista o lote
bundle exec rake "finture:demandas:reconciliar[50]"                # enfileira o lote (padrão 50, máx. 1000)
DRIFT=1 bundle exec rake "finture:demandas:reconciliar[50]"        # inclui synced com conteúdo diferente
bundle exec rake "finture:demandas:reconciliar_conversa[123]"      # uma conversa (id interno), reenvio forçado, agora
```

- **Lote:** no máximo `limit` conversas por execução; a seguinte pega as próximas, porque as aplicadas saem da seleção. É o controle de rajada: nada roda sozinho, e cada execução é limitada.
- **Por conversa:** `Finture::DemandaReconcileService.reconcile_conversation!(conversation_id)` (o mesmo que o rake) envia na hora, **mesmo** que o conteúdo seja igual ao último aplicado (ignora `last_payload_hash`).

Consultas pelo console:

```ruby
Finture::DemandaSync.where(status: %w[divergent failed]).pluck(:conversation_id, :status, :hub_motivo, :recovery_state, :rejected_at)
Finture::DemandaSync.awaiting_recovery.where(hub_motivo: 'futuro').pluck(:conversation_id, :recovery_state, :rejected_at)
```

## Troca de versão (v1 → v2) e volta

- **Hash de conteúdo:** `last_payload_hash` é calculado sempre no formato do v1 (mesmas chaves e ordem, `payload_version: 1`, sem `ocorrido_em`, `evento` e os campos do v2). Uma linha sincronizada pelo v1 tem o mesmo hash que o v2 calcula para o mesmo conteúdo.
- **Primeira execução depois do deploy:** nada é reenviado sozinho. Os envios continuam disparados só por mudanças; uma conversa sem mudança continua `unchanged` e só manda o v2 na próxima mudança relevante. A reconciliação com `DRIFT=1` também não vê diferença nas linhas do v1 por causa da versão. Linhas antigas ficam com `sequencia = 0` (o primeiro envio v2 sai com 1) e sem `elegivel_em` (campo omitido).
- **Voltar à imagem anterior (v1):** a migration só acrescenta colunas; o v1 ignora as novas. Uma linha `divergent` é tratada pelo v1 como não sincronizada (reenvia na próxima mudança). Jobs sem autor (n8n, automação, reconciliação em lote) têm os mesmos 2 argumentos do v1; os que levam autor (3 argumentos) ou são reenvio forçado por conversa (4), se ainda estiverem na fila no momento da volta, falham no v1 (`ArgumentError`): ou esvaziar a fila `low` antes, ou aceitar (a próxima mudança da conversa reenvia o estado completo). O HUB continua aceitando o v1. Sem trocar a imagem, `FINTURE_HUB_PAYLOAD_VERSION=1` faz o v2 enviar o v1 exato.

## Variáveis de ambiente

| Variável | Para quê |
|---|---|
| `FINTURE_HUB_BASE_URL` | Base do HUB, ex. `https://hub.example.test` |
| `FINTURE_HUB_INGEST_SECRET` | Mesmo valor de `DEMANDAS_INGEST_SECRET` no HUB (`openssl rand -hex 32`) |
| `FINTURE_HUB_PAYLOAD_VERSION` | Vazio = 2. `1` = payload v1 exato |

Vazio (as duas primeiras) = integração desligada (o listener sai antes de enfileirar). Configurar nas revisões **rails e sidekiq**: o listener roda nas duas (onde a conversa muda) e o envio roda no Sidekiq. Em desenvolvimento, HUB local em `http://localhost:8001` funciona direto; outro host exige `LOCAL_EGRESS_ALLOWLIST` (trava de `config/initializers/000_finture_local_isolation.rb`).

## Tabela `finture_demanda_syncs`

| Coluna | Significado |
|---|---|
| `conversation_id`, `external_id` | 1 linha por conversa; `external_id` = `chatwoot:<account_id>:<display_id>` |
| `hub_demanda_id` | id devolvido pelo HUB |
| `status` | `pending` (criada), `synced` (último envio aplicado), `retrying` (erro passageiro, job vai tentar), `divergent` (HUB recebeu e não aplicou), `failed` (HUB recusou ou tentativas esgotadas) |
| `last_event` | `created` ou `updated` do último envio aplicado |
| `last_payload_hash` | SHA-256 do conteúdo do último envio aplicado (formato v1, ver acima) |
| `sequencia`, `attempt_hash` | última sequência enviada; hash do último corpo enviado (retentativa reaproveita o número) |
| `elegivel_em` | instante registrado em que a conversa virou demanda |
| `hub_motivo` | `motivo` da última resposta (`futuro`, `atrasado`, `duplicado` ou null) |
| `recovery_state`, `rejected_at`, `recovered_at` | recuperação de envio não aplicado: `pending`, `recovered` ou `failed` |
| `last_sent_at`, `last_error`, `attempts` | diagnóstico |

## Ordem de deploy

1. HUB com suporte ao v2 (aceita v1 e v2). Se o HUB ainda não aceitar o v2, subir o Chatwoot com `FINTURE_HUB_PAYLOAD_VERSION=1`.
2. Chatwoot: `db:migrate` (`20261119120000`, só acrescenta colunas) e código.
3. Opcional, depois de validar: `rake finture:demandas:pendencias` e, se houver linhas `failed`/`divergent`, `reconciliar` em lotes.

## Validação ponta a ponta

1. Em caixa operacional, mover um card para Em atendimento sem responsável: nada chega ao HUB.
2. Atribuir um agente: a demanda chega com `elegivel_em` (instante da atribuição), `sequencia: 1` e `autor` = quem atribuiu pelo painel.
3. Gravar `sdr_next_action` pelo n8n (token de API): `plano_acao` atualizado, `sequencia` seguinte, sem `autor`, mesmo `elegivel_em`.
4. Resolver a conversa: `status_origem: resolved`.
5. HUB fora do ar (stub local): linha em `retrying`, sucesso quando voltar, sem evento duplicado. Segredo errado (stub local): `failed`; `reconciliar` reenvia depois de corrigido.
6. Relógio adiantado (stub respondendo `motivo: "futuro"`): linha `divergent` + `recovery_state: pending`; `reconciliar` aplica e marca `recovered`.

Testes de falha só em ambiente isolado (HUB local ou stub), nunca alterando o segredo ou as variáveis da integração compartilhada.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `app/listeners/finture/demanda_listener.rb` | Filtra o `conversation_updated` (síncrono), registra `elegivel_em`, captura o autor e enfileira |
| `app/jobs/finture/demanda_sync_job.rb` | Retentativas e marcação de `failed` |
| `app/services/finture/demanda_sync_service.rb` | Regra de elegibilidade, payload, sequência, tratamento da resposta |
| `app/services/finture/demanda_reconcile_service.rb` | Reconciliação em lote e por conversa |
| `app/services/finture/hub_client.rb` | HTTP com o HUB |
| `app/models/finture/demanda_sync.rb` | Estado do envio por conversa |
| `lib/tasks/finture_demandas.rake` | Rake de consulta e reconciliação |
| `db/migrate/20261112120000_create_finture_demanda_syncs.rb` | Tabela |
| `db/migrate/20261119120000_add_v2_fields_to_finture_demanda_syncs.rb` | Colunas do v2 e da recuperação |
| `lib/current.rb`, `app/controllers/concerns/access_token_auth_helper.rb` | Marca requisições por token de API (sem autor) |
| `app/dispatchers/sync_dispatcher.rb` | Registra o listener (síncrono) |
