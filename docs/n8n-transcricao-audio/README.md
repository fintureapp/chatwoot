# Transcrição de áudio na triagem por IA

O cliente manda áudio no WhatsApp e a triagem com IA responde como se fosse texto. Hoje os fluxos ignoram o áudio: o nó "Filtrar Evento" exige texto.

## Como funciona

```
Cliente manda áudio
  → Chatwoot salva a mensagem (o áudio original não muda)
  → Finture::AudioTranscriptionJob: baixa o arquivo do storage e chama o motor
  → grava no anexo: transcribed_text + finture_transcription (status, motor, confiança, duração, tempo)
  → message_updated → webhook do bot (n8n)
  → "Filtrar Evento" aceita o áudio transcrito e usa o texto como mensagem
  → o resto do fluxo é o de hoje (guard IA/humano → triagem → Haiku → resposta)
```

| status | Quando | O que o n8n faz |
|---|---|---|
| `ok` | Transcrição boa | Segue a triagem com o texto (o Haiku é avisado de que veio de áudio) |
| `unintelligible` | Motor devolveu nada, texto típico de silêncio ("Legendas pela comunidade Amara.org") ou confiança abaixo de `FINTURE_TRANSCRIPTION_MIN_CONFIDENCE` | 1ª vez: "Não consegui entender seu áudio, pode mandar de novo ou escrever?"; 2ª vez seguida: humano |
| `too_long` | Mais que `FINTURE_TRANSCRIPTION_MAX_SECONDS` (padrão 180 s) ou `FINTURE_TRANSCRIPTION_MAX_BYTES` | Pede áudio mais curto ou texto; 2ª vez seguida: humano |
| `failed` | Erro do motor que não passou com 3 tentativas | Igual a `unintelligible` |

- **Repetição do evento:** a transcrição roda uma vez por anexo, porque o Chatwoot trava o anexo e um status final não é refeito. No n8n, a chave `dedup:audio:<id>` vale 7 dias.
- **IA x humano:** o áudio passa pelo mesmo bloqueio do texto ("GET Estado Conversa" e "Em Atendimento Humano?"), mais a trava de envio do Assumir/Devolver.
- **Transcrição é conteúdo derivado:** na conversa aparece embaixo do áudio, com o rótulo "Transcrição automática". Tem o mesmo acesso da conversa e a mesma retenção da mensagem.
- **Na nota interna do handoff** aparece "[Mensagem recebida por áudio...]", para o atendente conferir o áudio original.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `mods-audio.js` | Os ajustes nos dois fluxos, aplicados por âncora de texto |
| `aplicar.js` | Aplica um ou mais arquivos de ajuste ao JSON do fluxo publicado e gera o código do SDK para `update_workflow` |
| `simular.js` | Roda os nós de código ajustados com eventos de áudio (ok, inaudível, 2ª falha, longo, número falado) sem n8n |

Os ajustes, iguais nos dois fluxos (Triagem Parceiros `jIzoOMeCcpXSmSnG` e Suporte Clientes `FutuZQcHKnslRXG8`):

1. **Filtrar Evento:** aceita `message_updated` de áudio recebido, sem texto, com `transcription_status`. O `message_created` do áudio continua de fora.
2. **Montar Dedup Key / Redis Dedup:** chave `dedup:audio:<id>` com TTL de 7 dias. O texto continua com `dedup:msg:<id>` e 5 min.
3. **Extrair Dados Chatwoot:** `origemAudio` e `audioStatus`; "um", "opção dois" etc. viram o dígito do menu.
4. **Motor Triagem:** áudio sem transcrição pede para repetir. A contagem fica em `audioFalhas`, no estado do Redis; na 2ª falha seguida, vai para o humano.
5. **Montar Body Haiku:** avisa que o texto veio de áudio. Se estiver confuso, pergunta; nunca inventa.
6. **Preparar Handoff:** a nota interna avisa que a demanda veio por áudio.

## Ordem do deploy

1. **Motor de transcrição.**
   - Na Azure: recurso Azure OpenAI com um deployment do `gpt-4o-mini-transcribe` (conferir se o modelo está disponível na região).
   - Alternativa: chave da OpenAI com `FINTURE_TRANSCRIPTION_PROVIDER=openai`.
2. **Chatwoot.**
   - Deploy desta branch e `rails db:migrate` (coluna `finture_inbox_configs.audio_transcription_enabled`).
   - No Container App: `FINTURE_TRANSCRIPTION_API_KEY`, `FINTURE_TRANSCRIPTION_ENDPOINT` e `FINTURE_TRANSCRIPTION_MODEL` (o nome do deployment). As outras variáveis têm padrão (ver `.env.example`).
   - Sem a chave, nada muda.
3. **Modo sombra (2 a 3 dias).**
   - Com "Atendimento com IA" ligado nas caixas 4, 12 e 20, os áudios já são transcritos e aparecem para os atendentes.
   - O n8n ainda ignora os áudios, porque o filtro antigo exige texto.
   - Conferir a qualidade nas conversas reais.
4. **Amostra (critério de aceite).**
   - Rodar `rake "finture:transcription:sample[/pasta]"` numa pasta com 30 a 50 áudios, sintéticos ou reais autorizados. Para cada áudio, opcionalmente, um `.txt` com o texto esperado.
   - Sai um CSV por áudio e um resumo: WER médio, termos-chave acertados, latência p50/p95, minutos e custo estimado (`FINTURE_TRANSCRIPTION_USD_PER_MIN`, padrão 0,003).
   - Sugestão de meta: termos-chave ≥ 90% e p95 < 15 s.
   - Ajustar `FINTURE_TRANSCRIPTION_MIN_CONFIDENCE` se o motor descartar áudio bom ou deixar passar áudio ruim.
5. **n8n**, depois do pacote `../n8n-modo-atendimento`, se ele ainda não tiver sido aplicado. É ele que tira os tokens de dentro dos nós.
   1. Salvar o `get_workflow_details` de cada fluxo publicado (`suporte.json`, `parceiros.json`).
   2. `node simular.js suporte.json parceiros.json [../n8n-modo-atendimento/mods.js]`: precisa dar `ok` em tudo.
   3. `node aplicar.js suporte.json suporte.workflow.js [../n8n-modo-atendimento/mods.js] mods-audio.js` (o mesmo para parceiros).
      - **Não commitar a saída:** sem o `mods.js` do modo de atendimento, ela leva os tokens em texto puro do fluxo publicado.
   4. `validate_workflow` e depois `update_workflow`. Isso cria um rascunho; vincular as credenciais no editor, se o pacote do modo de atendimento entrou junto.
   5. Testar pelo webhook de teste (áudio bom, áudio mudo, áudio longo, áudio com humano atendendo) e publicar.
6. **Conferir o gatilho da caixa 4.**
   - A caixa 12/20 recebe pelo AgentBot, que já repassa `message_updated`.
   - Se a Triagem Parceiros for disparada por webhook de conta, marcar também o evento "Mensagem atualizada" nesse webhook. Sem isso, o áudio não chega.

## Para desligar

- **Sem transcrição:** tirar `FINTURE_TRANSCRIPTION_API_KEY`. Os áudios voltam a ser ignorados pela triagem, como antes.
- **Só uma caixa:** desligar "Atendimento com IA" (e "Transcrição de áudio") nela.
