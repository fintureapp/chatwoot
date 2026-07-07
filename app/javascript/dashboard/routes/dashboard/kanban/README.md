# Kanban SDR AI — visão geral (v2)

Ferramenta operacional para acompanhamento das demandas comerciais/SDR dentro do
Finture Chat. Cada **card é uma conversa** do Chatwoot; a etapa e os campos SDR vivem
em `conversation.custom_attributes` (sem tabela/coluna nova).

## Modelo de dados (custom_attributes da conversa)

| Chave                | Tipo   | Uso                                                     |
| -------------------- | ------ | ------------------------------------------------------- |
| `sdr_stage`          | string | Etapa atual (valores em `config/stages.js`).            |
| `sdr_next_action`    | string | Próxima ação da demanda (editável no drawer).           |
| `sdr_lost_reason`    | string | Motivo da perda (ao mover para "Perdido").              |
| `sdr_lost_comment`   | string | Observação da perda (opcional).                         |
| `sdr_history`        | array  | Log de mudanças de etapa (`{from,to,at,by,origin}`).    |

Campos de negócio já usados no card: `valor_potencial` (volume), `produto_interesse`.

> `sdr_history` é um **array em jsonb**. O validador do backend
> (`jsonb_attributes_length`) só limita String (<1500) e Integer, então arrays passam
> sem cap — por isso limitamos a **20 entradas** no cliente (`HISTORY_MAX_ENTRIES`).

## Fluxo de dados

- **Carregamento:** `KanbanSDRPage` → `store/modules/kanban.js#fetchBoard` → **1 chamada**
  a `GET conversations/kanban` (endpoint enxuto no backend). O payload traz só os campos
  do card — sem `messages[]`, `last_non_activity_message` nem `unread_count` (que causavam
  N+1 no `#index`).
- **Filtros/busca/ordenação:** 100% client-side na página (sem refetch). Ordenação padrão:
  **última atualização (desc)**.
- **Detalhe:** clique no card abre o `KanbanCardDrawer` (drawer lateral). Detalhes vêm do
  card já carregado (abertura instantânea); só as **notas** são buscadas sob demanda.
- **Persistência de etapa/próxima ação:** `POST conversations/:id/custom_attributes`
  (substitui o hash inteiro — o store faz merge).
- **Notas:** mensagens privadas (`POST conversations/:id/messages` com `private: true`).

## Backend (fork — aditivo, sem migração)

- Rota: `get :kanban` (collection) em `config/routes.rb`.
- Ação: `ConversationsController#kanban` — escopo/permrmissão reusam `assigned_inboxes`
  + `Conversations::PermissionFilterService` (mesmo caminho do `#index`); cap de 1000.
- View: `app/views/api/v1/accounts/conversations/kanban.json.jbuilder` (payload enxuto).

Rollback do endpoint = apagar rota+ação+view (nenhum schema tocado).

## Limitações conhecidas

- **Notas:** o drawer lista a página mais recente de mensagens filtrando as privadas;
  notas muito antigas aparecem apenas na conversa completa. `precisa ser validado` para
  conversas com histórico muito longo.
- **Histórico estruturado:** só cobre **mudanças de etapa** (a partir desta versão).
  Mudanças de status/assignee/label existem apenas como texto nas activity messages.
- **Permissões:** herdadas de `ConversationPolicy#show?`. No community **não há** permissão
  separada de "editar atributos": quem enxerga a conversa pode mover/editar/notar.
- **Board cap:** 1000 cards por carga; acima disso é preciso paginação/virtualização.

## Passo de dados recomendado (opcional)

Criar as definições de custom attribute (`conversation_attribute`) para `sdr_stage`,
`sdr_next_action`, `sdr_lost_reason` em Configurações → Atributos personalizados, para que
também fiquem visíveis/editáveis no painel padrão da conversa. É **dado**, não migração.
