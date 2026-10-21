# LOCAL DEVELOPMENT — Chatwoot Finture (Docker)

Ambiente **local, isolado e descartável** do fork Finture do Chatwoot (base upstream
4.15.1, commit `64b0ebd8d`). Serve para desenvolver UI/backend, testar migrations,
Sidekiq, canais simulados, anexos, usuários, times, caixas, conversas e permissões.

> **Regra inegociável:** nada aqui conecta em produção (PostgreSQL Cloudify, Redis,
> Azure Storage, SMTP, Meta/WhatsApp, n8n, AgentBots, webhooks). O isolamento é
> imposto por código e por rede, não só por esta documentação (ver
> [Segurança](#segurança-e-isolamento)). **Nunca** copie valores do `.env.prod`.

## Sumário

1. [Arquitetura](#arquitetura)
2. [Requisitos (Windows + Docker Desktop + WSL2)](#requisitos)
3. [Primeiro uso](#primeiro-uso)
4. [Comandos do dia a dia](#comandos)
5. [Serviços e portas](#serviços-e-portas)
6. [Banco, migrations, seeds e reset](#banco-migrations-seeds-e-reset)
7. [Redis e Sidekiq](#redis-e-sidekiq)
8. [Frontend e hot reload](#frontend-e-hot-reload)
9. [Storage, e-mail e integrações](#storage-e-mail-e-integrações)
10. [Segurança e isolamento](#segurança-e-isolamento)
11. [Testes e validação](#testes-e-validação)
12. [Depuração e logs](#depuração-e-logs)
13. [Problemas comuns](#problemas-comuns)
14. [Orientações para coding agents](#orientações-para-coding-agents)
15. [Baseline a partir de produção (processo separado)](#baseline-a-partir-de-produção)

---

## Arquitetura

Tudo roda em containers. O host precisa apenas de Docker Desktop e Git; não é preciso
instalar Ruby, Node ou PostgreSQL no Windows.

```
 navegador ──► 127.0.0.1:3000 / :3036
                    │
              ┌─────▼─────┐  rede "edge" (com internet, só para publicar portas)
              │   edge    │  nginx: proxy HTTP + WebSocket (ActionCable e HMR)
              └─────┬─────┘
 ═══════════════════╪═════════════ rede "app" (internal: true — SEM rota para a internet)
     ┌──────────┬───┴──────┬───────────┬───────────┬──────────┬──────────────┐
   rails     sidekiq     vite      postgres     redis     mailpit     webhook-sink
   (Puma)   (filas+cron) (HMR)    (pgvector)   (AOF)    (SMTP+UI)   (mocks Meta/webhooks)

 one-shots: deps (pnpm install; único com internet, sem variáveis do app)
            db-prepare (db:chatwoot_prepare + seeds Finture)
```

| Componente | Versão | Origem |
|---|---|---|
| Ruby / Rails / Puma | 3.4.4 / 7.1 / 7.2 | `.ruby-version`, `Gemfile.lock` |
| Sidekiq + sidekiq-cron | 7.3 | `config/sidekiq.yml`, `config/schedule.yml` |
| Node / pnpm / Vite | 24.13 / 10.2 / 6.4.2 | `.nvmrc`, `package.json` |
| PostgreSQL | 16 + pgvector 0.8.7 | extensões do `db/schema.rb`: `vector`, `pg_trgm`, `pgcrypto`, `pg_stat_statements` |
| Redis | 7.4 | mesma família do compose upstream |
| Mailpit | 1.31 | captura SMTP |

**Por que tudo em container e não híbrido?** No Windows não há Ruby nativo prático, e o
`pg`/`nokogiri`/`grpc` exigem toolchain. Em container o setup é idêntico para pessoas e
coding agents, e a rede interna garante o isolamento. O custo é o I/O de bind mount no
Windows (ver [Problemas comuns](#problemas-comuns)).

**Por que um compose novo (`docker-compose.local.yaml`)?** O `docker-compose.yaml`
upstream instala gems em runtime, expõe portas em `0.0.0.0`, usa Postgres sem senha
(e um volume que não persiste dados) e Mailhog. Ele foi mantido intacto para não gerar
conflito em merges do upstream.

### Customizações Finture preservadas

O ambiente roda o código do fork como está: Kanban SDR (etapas por caixa, cotações,
follow-ups, histórico/desfechos), classificação comercial/operacional da caixa, dashboard
SDR, sino de notificações por time, presença online, separação de canais
WhatsApp/E-mail. As 7 migrations `db/migrate/2026*_finture_*`/`*_operational_*` rodam
pelo fluxo normal de migrations.

## Requisitos

1. **Windows 10/11 com virtualização habilitada.**
2. **WSL2** (motor do Docker Desktop). Em um PowerShell **como administrador**:
   ```powershell
   wsl --install --no-distribution
   ```
   Reinicie o Windows. Confira com `wsl --status`.
3. **Docker Desktop** com "Use the WSL 2 based engine" ligado. Recomendado reservar
   ≥ 6 GB de RAM e 4 CPUs (Settings → Resources).
4. **Git for Windows** (inclui o Git Bash, onde rodam os scripts). `make` é opcional: no
   Windows use `bash script/local-dev <comando>`; no WSL/macOS/Linux, `make <alvo>`.

### Modo do código: `sync` (Windows) ou `bind` (WSL/Linux/macOS)

Medido nesta máquina: com o repositório no OneDrive montado direto no container
(bind mount), listar os ~6.700 arquivos de `app/config/lib` levava 17 s, cada
requisição com o watcher por polling levava 33–40 s, e uma compilação de SCSS levava
5 minutos. Além disso, o Docker Desktop **não repassa eventos de arquivo** de pastas
do Windows. Por isso, o padrão no Windows é o modo **sync**:

- o `dev` copia o código uma vez para o volume Linux `app_src` (sem `.git`, `.env*`,
  dumps nem `node_modules`) e roda `docker compose watch` em segundo plano;
- cada arquivo salvo no Windows (editor, Claude Code, `git checkout`) chega ao
  container em ~1 s, e o Rails e o Vite recebem eventos nativos (sem polling);
- arquivos **gerados dentro do container** não voltam sozinhos. Traga-os com
  `bash script/local-dev pull db/schema.rb db/migrate`. O `db-migrate` já faz o pull
  do `db/schema.rb`;
- se você fechar o terminal e a sincronização parar, `bash script/local-dev status`
  avisa e `bash script/local-dev sync` religa. `reseed-source` recopia tudo.

No modo **bind** (repositório clonado dentro do WSL, `\\wsl$\...`), o container lê o
repositório diretamente e nada disso é necessário. Força-se um modo com
`LOCAL_CODE_MODE=sync|bind` no `.env.local`.

> **Memória:** o ambiente completo usa ~1,6 GB nos containers, mas a VM do Docker
> Desktop reserva por padrão até metade da RAM. Em máquinas de 16 GB, limite a VM
> criando `%UserProfile%\.wslconfig` com `[wsl2]` e `memory=6GB`, e rode
> `wsl --shutdown`.

## Primeiro uso

**Windows — um comando só**, na raiz do projeto (PowerShell, cmd ou duplo clique no arquivo):

```powershell
.\subir-local.cmd
```

Ele encontra o Git Bash, abre o Docker Desktop se estiver fechado (e espera o motor),
roda `script/local-dev dev` (gera `.env.local`, build da imagem, deps, banco, migrations,
seeds, serviços e sincronização) e abre http://localhost:3000. Para parar:
`.\parar-local.cmd` (dados preservados).

Equivalente manual, no Git Bash / WSL / macOS / Linux:

```bash
bash script/local-dev setup   # gera .env.local com segredos LOCAIS aleatórios
bash script/local-dev dev     # build da imagem, deps, banco, migrations, seeds e serviços
```

O primeiro `dev` leva vários minutos (build de gems + `pnpm install`). Os seguintes
levam segundos. Ao final aparecem as URLs.

Login: `admin@finture.example` com a senha `LOCAL_SEED_PASSWORD` do `.env.local`
(padrão documentado `Finture@Local2026`). O upstream também cria `john@acme.inc` /
`Password1!` (conta "Acme Inc"), igualmente fictício.

### `.env.local`

Gerado a partir do `.env.local.example`. Contém **só** segredos locais aleatórios
(`SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`), a senha das seeds e portas
opcionais. Hosts de banco/Redis/SMTP/storage e `FRONTEND_URL` ficam fixos no compose e
**sobrescrevem** o que estiver no arquivo. Para gerar um segredo manualmente:
`openssl rand -hex 64`.

Comparação com as variáveis de produção (somente nomes):

| Variável de produção | No local |
|---|---|
| `RAILS_ENV`, `NODE_ENV` | `development` (fixo) |
| `INSTALLATION_ENV` | `docker` |
| `FRONTEND_URL` | `http://localhost:3000` (fixo) |
| `FORCE_SSL` | `false` (boot falha se `true`) |
| `SECRET_KEY_BASE` | gerado localmente |
| `POSTGRES_HOST/PORT/DATABASE/USERNAME/PASSWORD` | `postgres:5432`, `chatwoot_local_dev`, `chatwoot_local`, senha local |
| `REDIS_URL`, `REDIS_PASSWORD` | `redis://redis:6379/0`, senha local |
| `ACTIVE_STORAGE_SERVICE` | `local` (boot falha se outro) |
| `AZURE_STORAGE_ACCOUNT_NAME/ACCESS_KEY/CONTAINER` | **ausentes** (boot falha se preenchidas) |
| `AZURE_APP_ID`, `AZURE_APP_SECRET` | **ausentes** (boot falha se preenchidas) |
| `SMTP_ADDRESS/PORT` | `mailpit:1025`, sem TLS |
| `SMTP_USERNAME/PASSWORD/AUTHENTICATION/DOMAIN` | **ausentes** (boot falha se usuário/senha preenchidos) |
| `MAILER_SENDER_EMAIL` | `Finture Local <nao-responda@finture.example>` |
| `DEFAULT_LOCALE` | `pt_BR` |
| `RAILS_LOG_TO_STDOUT` | `true` |

## Comandos

| Objetivo | Windows (Git Bash) | WSL / macOS / Linux |
|---|---|---|
| Subir tudo | `bash script/local-dev dev` | `make dev` |
| Parar (mantém dados) | `bash script/local-dev stop` | `make stop` |
| Logs (todos) | `bash script/local-dev logs` | `make logs` |
| Logs Rails / Sidekiq | `... logs-web` / `... logs-worker` | `make logs-web` / `make logs-worker` |
| Migrations | `... db-migrate` | `make db-migrate` |
| Seeds Finture | `... db-seed` | `make db-seed` |
| Recriar só o banco | `... db-reset` | `make db-reset` |
| Testes Ruby | `... test spec/models` | `make test ARGS="spec/models"` |
| Testes JS | `... test-js` | `make local-test-js` |
| Provar isolamento | `... check` | `make local-check` |
| Simular fluxos | `... simulate` | `make local-simulate` |
| Console Rails / psql / bash | `... console` / `db-console` / `shell` | `make local-console` / `local-db-console` / `local-shell` |
| Limpeza | `... clean [--volumes\|--image\|--all]` | `make clean ARGS="--volumes"` |

**Parar × reiniciar × recriar × resetar × excluir volumes:**

- `stop`: pausa os containers. Nada é perdido.
- `restart [serviço]`: reinicia processos (ex.: depois de mudar initializer ou gem já instalada).
- `build`: recria a imagem. Necessário quando o `Gemfile.lock` muda (o container avisa).
  Quando o `pnpm-lock.yaml` muda, rode `deps` (o Vite avisa).
- `down`: remove containers e redes. Volumes (dados) ficam.
- `db-reset`: apaga e recria **só** o banco local e limpa o Redis. Anexos e e-mails ficam.
- `clean --volumes`: apaga **todos** os dados locais (banco, Redis, anexos, e-mails,
  node_modules). Pede confirmação digitando `apagar-dados`.

## Serviços e portas

Todas as portas são publicadas **somente em 127.0.0.1**.

| Serviço | URL / porta | Observação |
|---|---|---|
| Chatwoot (via edge) | http://localhost:3000 | UI, API, ActionCable em `/cable` |
| Vite HMR (via edge) | 127.0.0.1:3036 | WebSocket de hot reload |
| Mailpit | http://localhost:8025 | todos os e-mails enviados |
| Webhook sink | http://localhost:8099/_requests | tudo que "sairia" para Meta/webhooks |
| Sidekiq Web | http://localhost:3000/monitoring/sidekiq | entre antes em http://localhost:3000/super_admin com `admin@finture.example` |
| PostgreSQL | 127.0.0.1:5432 | `chatwoot_local` / senha do `.env.local` |
| Redis | 127.0.0.1:6379 | senha do `.env.local` |

Portas de Postgres/Redis/Mailpit/sink podem mudar via `LOCAL_*_PORT` no `.env.local`.
3000 e 3036 são fixas (cookies, `FRONTEND_URL` e HMR dependem delas).

## Banco, migrations, seeds e reset

- **Preparação:** o serviço `db-prepare` roda `bin/rails db:chatwoot_prepare`. Em banco
  vazio, ele carrega `db/schema.rb`, roda `db:seed` (upstream) e depois as migrations.
  Em banco existente, só aplica as migrations pendentes. Em seguida, roda
  `finture:local:seed`. As migrations versionadas são a fonte de verdade; não há dump.
- **Migrations novas:** crie normalmente (`bash script/local-dev shell` →
  `bin/rails g migration ...`) e aplique com `db-migrate`. O `db/schema.rb` é atualizado
  no seu working tree.
- **Seeds Finture** (`db/seeds/finture_local.rb`, idempotentes): conta "Finture (Local)",
  admin (super admin), supervisora e um agente por time; times Saúde, Vida,
  Consórcio/Crédito, Corporate e Elementares; caixas WhatsApp Comercial (simulado),
  E-mail Operacional (simulado), API Integração (simulada) e Site (widget); funis
  comercial/operacional; 12 conversas em todos os estados (aberta, pendente, resolvida,
  adiada), com atribuições, etiquetas, notas internas, anexos, prioridade, cotações,
  follow-ups, ganho/perdido; atributos personalizados; automações de triagem; respostas
  prontas; notificações; e o agente **Gabriel Sem Acesso** (sem time e sem caixa), para
  testar permissões. Domínios `.example` e telefones com DDD 00: nada é real.
- **Reset** (`db-reset`): pede que você digite `reset`, valida que o destino é
  `chatwoot_local_dev@postgres` (rake `finture:local:assert_safe_db`, que aborta para
  qualquer outro host ou nome com cara de produção), faz drop/create, prepara, semeia e
  limpa o Redis.
- **Versão do PostgreSQL de produção:** não foi consultada (exigiria acesso ao Cloudify).
  Usamos PG 16 + pgvector, a versão suportada pelo compose upstream. Pendência: confirmar
  com quem administra o Cloudify.

## Redis e Sidekiq

- O Redis local exige senha e usa AOF (`redis_data`). Banco 0 é do dev; banco 1 é dos testes.
- O Sidekiq usa `config/sidekiq.yml` (todas as filas) com concorrência 5. Os crons de
  `config/schedule.yml` rodam normalmente. Nenhum deles chama serviço externo em
  development: a checagem de versão no Chatwoot Hub só roda em produção, o fetch IMAP
  só atua em caixas com IMAP (as seeds não criam nenhuma) e o push relay está desligado
  (`ENABLE_PUSH_RELAY_SERVER=false`).
- Jobs que tentam sair (ex.: webhook configurado para uma URL externa) falham com
  `FintureLocalIsolation::BlockedEgressError` e entram no retry padrão (máx. 3). Isso é
  esperado e aparece em `make logs-worker`.

## Frontend e hot reload

- O Vite roda no container `vite` (`ruby bin/vite dev`). O Rails faz proxy de
  `/vite-dev/*` para `vite:3036` (`VITE_RUBY_HOST=vite`). O navegador abre o WebSocket de
  HMR em `localhost:3036`, que o edge repassa ao Vite. A primeira carga do dashboard
  compila todos os módulos e é lenta; as seguintes ficam em cache no Vite.
- Rails e Vite usam eventos de arquivo (inotify), que funcionam nos modos sync e bind
  dentro do WSL. Polling (`LOCAL_RAILS_FILE_WATCHER_POLLING` / `LOCAL_VITE_USE_POLLING`
  no `.env.local`) só existe para o caso raro de bind mount de pasta Windows, e é lento.
- Os comandos usam `ruby bin/rails` e `ruby bin/vite` em vez do shebang: no checkout do
  Windows (`core.autocrlf=true`) os binstubs têm CRLF e o shebang falha com `ruby\r`.
- Cookies e sessão funcionam em `http://localhost:3000` (`FORCE_SSL=false`).
  O ActionCable usa o Redis local.

## Storage, e-mail e integrações

- **Active Storage:** serviço `local` (disco) no volume `storage`. Avatares, anexos,
  pré-visualizações e exclusão funcionam como em produção, sem Azure. O Azurite não foi
  adicionado porque nada no fork depende de operações específicas de blob storage.
- **E-mail:** todo envio (convites, recuperação de senha, notificações, respostas de
  caixas de e-mail) vai para o Mailpit. Não há relay configurado, então nada sai.

### Matriz de integrações

| Integração | Classificação | Como fica no local | Como testar |
|---|---|---|---|
| PostgreSQL (Cloudify) | **local** | container `postgres` | `make local-db-console` |
| Redis | **local** | container `redis` com senha | `make logs-worker` |
| Azure Storage | **desabilitada → local** | `ACTIVE_STORAGE_SERVICE=local`; variáveis Azure barradas no boot | upload/download na UI; `simulate` (etapa E) |
| SMTP | **local (mock)** | Mailpit | http://localhost:8025; `simulate` (etapa D) |
| Entrada de e-mail (Action Mailbox) | **local** | `ActionMailbox::InboundEmail` direto, sem IMAP | `simulate` (etapa D) |
| WhatsApp Cloud / Meta | **mock** | `WHATSAPP_CLOUD_BASE_URL=http://webhook-sink:8080` responde como a Graph API; entrada via `POST /webhooks/whatsapp/:numero` assinado com segredo fictício | `simulate` (etapa A); fixture `docker/local/fixtures/whatsapp_inbound_text.json` |
| Cadastro de webhooks na Meta (`setup_webhooks`) | **desabilitada** | seeds não disparam; URL da Graph é fixa no código e o egress está bloqueado | — |
| Instagram, Facebook, Telegram, Line, Twilio, TikTok | **desabilitada** | sem credenciais; egress bloqueado | `make local-check` |
| Inbox API (webhook de saída) | **mock** | `webhook_url` aponta para o sink | `simulate` (etapa C); http://localhost:8099/_requests |
| Webhooks de conta / AgentBots | **mock ou desabilitada** | seeds não criam nenhum; se você criar, use `http://webhook-sink:8080/...` (o egress para qualquer outro host é bloqueado) | criar na UI e conferir no sink |
| n8n (SDR IA, resumo por IA) | **desabilitada / mock** | o n8n chama a API do Chatwoot; no local, simule com `curl` na API (`source: 'n8n'`) | API `/api/v1/accounts/:id/...` com token local |
| IA (OpenAI/Captain) | **desabilitada** | sem chave; `OPENAI_API_KEY` barrada no boot | — |
| Login Microsoft/Azure (`AZURE_APP_*`) | **desabilitada** | variáveis barradas no boot | — |
| Push web/mobile (VAPID, relay do Hub) | **desabilitada** | relay desligado; VAPID locais gerados no banco | o sino interno funciona (notificações in-app) |
| Chatwoot Hub (telemetria/versão) | **desabilitada** | só roda em produção + `DISABLE_TELEMETRY` + egress bloqueado | — |
| Widget web | **local** | caixa "Site Finture (widget)" | `/widget_tests` ou script do widget numa página local |
| Sentry/Datadog/NewRelic | **desabilitada** | variáveis barradas no boot | — |

## Segurança e isolamento

Quatro camadas independentes:

1. **Compose:** hosts de banco/Redis/SMTP/storage fixados em `environment`, que vence
   qualquer `.env`. Portas apenas em `127.0.0.1`.
2. **Rede:** Rails, Sidekiq e Vite ficam só na rede `app` (`internal: true`), sem rota
   para a internet. Só o one-shot `deps` (pnpm) acessa a internet, e ele não recebe
   nenhuma variável da aplicação.
3. **Trava de boot** (`config/initializers/000_finture_local_isolation.rb`): em
   development (e em test com `FINTURE_LOCAL_ISOLATION=enforce`), o Rails (server,
   Sidekiq, console e rake) **aborta** se banco, Redis, SMTP ou qualquer `*_URL`/`*_HOST`
   apontar para fora da allowlist, se o nome do banco parecer produtivo, se o storage não
   for local, se `FORCE_SSL` estiver ligado, ou se houver credenciais produtivas
   preenchidas. A mensagem cita só nomes de variáveis.
4. **Trava de egress:** em development, toda conexão TCP aberta por Ruby (Net::HTTP,
   HTTParty, Faraday, SMTP, redis-client...) só vai para a allowlist
   (`postgres redis mailpit webhook-sink vite rails sidekiq edge`, loopback e
   `LOCAL_EGRESS_ALLOWLIST`). O resto levanta `BlockedEgressError`.

Também: o `entrypoint.sh` confere host/nome de banco e Redis antes de iniciar; o
`db-reset` aborta fora do banco local; `.env`, `.env.*` (exceto exemplos), dumps e
backups estão no `.gitignore`; o `script/local-dev scan-secrets` procura valores do
`.env.prod` em arquivos versionados e no histórico do fork, e imprime **só nomes de
chaves**. O sink mascara cabeçalhos de autenticação e tokens em query string.

Para liberar conscientemente um sandbox (ex.: número de teste da Meta), adicione o host a
`LOCAL_EGRESS_ALLOWLIST` **e** saiba que a rede `app` continua sem internet. Isso exige
uma decisão explícita de alterar o compose e deve passar por revisão.

## Testes e validação

```bash
bash script/local-dev check      # isolamento: boot, egress Ruby, rede e boots com config produtiva simulada
bash script/local-dev simulate   # fluxos ponta a ponta (ambiente precisa estar de pé)
bash script/local-dev test spec/models/finture spec/services/finture   # rspec (banco chatwoot_local_test)
bash script/local-dev test-js    # vitest
```

O `simulate` cobre: webhook Meta assinado (e recusa sem assinatura), contato e conversa
criados pelo Sidekiq, automação atribuindo time e etiqueta, broadcast ActionCable
(capturado no Redis), resposta do agente entregue ao WhatsApp simulado, mudança de
status e atribuição com notificação, inbox API com webhook capturado, e-mail de entrada
pelo Action Mailbox, resposta e recuperação de senha no Mailpit, e upload, download e
exclusão de anexo. Cada etapa imprime PASS/FAIL, e o comando sai com código ≠ 0 se algo
falhar.

O realtime no **navegador** precisa de checagem manual: abra a mesma conversa em duas
abas, rode `simulate` e veja a mensagem aparecer sem recarregar.

Specs de sistema (Capybara + Chrome) não rodam na imagem, que não tem navegador.

## Depuração e logs

- `make logs-web` / `make logs-worker`: logs do Rails e do Sidekiq em stdout.
- `byebug`/`debugger`: coloque o breakpoint, rode `bash script/local-dev attach rails`
  (ou `sidekiq`) e interaja. Para sair sem matar o processo, use `Ctrl-P Ctrl-Q`.
- `bash script/local-dev console`: Rails console (a trava de egress também vale aqui).
- Bullet (N+1) escreve no log do Rails.

## Problemas comuns

| Sintoma | Causa / solução |
|---|---|
| `failed to connect to the docker API ... dockerDesktopLinuxEngine` | Docker Desktop parado ou WSL2 ausente. Instale o WSL2 (Requisitos) e abra o Docker Desktop. |
| `Gemfile.lock mudou desde o build da imagem` | `bash script/local-dev build` e depois `dev` |
| `node_modules desatualizado` | `bash script/local-dev deps` |
| `[finture-local] Inicialização bloqueada` | Alguma variável aponta para fora do local. A mensagem lista os nomes; corrija o `.env.local` ou o ambiente do shell. |
| `Conexão externa bloqueada: host:porta` | Código tentou sair. Aponte a integração para `webhook-sink`/`mailpit`. |
| Porta 5432/6379/8025 em uso | Ajuste `LOCAL_*_PORT` no `.env.local`. |
| `$'\r': command not found` em scripts | Arquivo com CRLF de um clone antigo. O `.gitattributes` força LF nos arquivos do ambiente local; faça um clone novo ou `git checkout -- script/local-dev docker/local` (descarta mudanças locais nesses arquivos). |
| Requisições de 30 s+, SCSS de minutos | Bind mount de pasta Windows. Use o modo sync (padrão no Windows) ou clone dentro do WSL. |
| Edição no Windows não aparece no app | Modo sync com a sincronização parada: `bash script/local-dev status` e `bash script/local-dev sync`. |
| `/usr/bin/env: 'ruby\r'` | Binstub com CRLF executado direto. Use `ruby bin/rails ...` (o script já faz isso). |
| `mini-profiler-resources/includes.js` 500 | Problema do upstream (`Rack::File` não existe no Rack 3); não afeta o app. |
| Claude Code/terminal encerrado por falta de memória | Limite a VM do Docker no `.wslconfig` (seção Requisitos). |
| `the input device is not a TTY` (Git Bash) | Use os comandos do script, que aplicam `winpty`, ou rode pelo PowerShell. |

## Orientações para coding agents

- Use **apenas** `script/local-dev` / `make` para operar o ambiente. Não rode `docker
  compose` com outro arquivo nem `bin/rails` no host.
- Nunca leia, copie ou cite valores do `.env.prod`. Para comparar, use
  `script/local-dev scan-secrets`, que imprime só nomes de chaves.
- Não altere a allowlist, o `internal: true` da rede `app` nem o initializer de
  isolamento para "fazer um teste passar". Se precisar de um serviço novo, simule-o no
  `webhook-sink` ou acrescente um mock local.
- Antes de afirmar que algo funciona, rode `check` e `simulate` e cite o resultado.
- Novas seeds: acrescente em `db/seeds/finture_local.rb`, sempre idempotentes, com
  domínios `.example` e telefones `+55009000xxxxx`.

## Baseline a partir de produção

**Não existe e não deve existir cópia automática de produção.** Se um dia for
indispensável reproduzir um caso com dados reais, o processo é separado e exige
**autorização explícita** de quem responde pelos dados:

1. backup controlado, feito por quem administra o Cloudify, nunca por este ambiente;
2. restauração temporária em instância isolada, fora desta máquina de dev;
3. anonimização e sanitização validadas: nomes, e-mails, telefones, CPFs, conteúdo de
   mensagens, anexos, tokens (`access_tokens`, `channel_*`, `webhooks`, `agent_bots`,
   `installation_configs`, `integrations_hooks`), senhas e VAPID;
4. verificação independente de que dados pessoais e segredos foram removidos;
5. só então gerar uma baseline segura, documentada e com prazo de descarte.

Mesmo assim, as migrations versionadas seguem como fonte de verdade da estrutura.
