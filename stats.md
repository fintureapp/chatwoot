# Captain Assistant Metrics — Exploration

Candidate metrics for a per-assistant overview page, sourced from `messages`,
`conversations`, `reporting_events`, and the `captain_*` tables.

## Grounding facts

- **Assistant → messages**: `Captain::Assistant has_many :messages, as: :sender` → Captain
  messages are rows in `messages` with `sender_type = 'Captain::Assistant'`,
  `sender_id = <assistant.id>`. Most reliable per-assistant attribution.
- **Assistant → inboxes → conversations**: `captain_inboxes(captain_assistant_id, inbox_id)`.
- **Reporting events** (in `reporting_events`, scoped by `conversation_id`/`inbox_id`, no
  assistant column): `conversation_captain_inference_resolved`,
  `conversation_captain_inference_handoff`, `conversation_bot_resolved`,
  `conversation_bot_handoff`, `conversation_resolved`, `conversation_opened`
  (value > 0 = a reopen).
- **Enums**: `messages.message_type` → `incoming:0, outgoing:1`; `conversations.status` →
  `open:0, resolved:1, pending:2, snoozed:3`; `captain_assistant_responses.status` →
  `pending:0, approved:1`.

All queries take `:assistant_id`, `:account_id`, and a `:start`/`:end` window.

---

## Conversations Handled

Definition: How many distinct conversations this assistant actually participated in (sent at
least one message). Your denominator for every rate below, and the headline "is anyone using
this assistant" volume number.

```sql
SELECT COUNT(DISTINCT m.conversation_id) AS conversations_handled
FROM messages m
WHERE m.account_id = :account_id
  AND m.sender_type = 'Captain::Assistant'
  AND m.sender_id   = :assistant_id
  AND m.created_at BETWEEN :start AND :end;
```

## Auto-Resolution (Deflection) Rate

Definition: Of the conversations Captain handled, the share it closed on its own with no human
reply. This is the core ROI/deflection signal — higher means more tickets the team never had
to touch.

```sql
WITH handled AS (
  SELECT DISTINCT conversation_id
  FROM messages
  WHERE account_id = :account_id
    AND sender_type = 'Captain::Assistant'
    AND sender_id   = :assistant_id
    AND created_at BETWEEN :start AND :end
)
SELECT
  COUNT(DISTINCT re.conversation_id)::float
    / NULLIF((SELECT COUNT(*) FROM handled), 0) AS auto_resolution_rate
FROM reporting_events re
JOIN handled h ON h.conversation_id = re.conversation_id
WHERE re.account_id = :account_id
  AND re.name IN ('conversation_captain_inference_resolved',
                  'conversation_bot_resolved');
```

## Handoff Rate

Definition: Of the conversations Captain handled, the share it escalated to a human (either an
explicit handoff tool call mid-chat, or the auto-resolve job deciding the customer still needs
clarification). Inverse signal to deflection — tells you how often Captain hit its limits.

```sql
WITH handled AS (
  SELECT DISTINCT conversation_id
  FROM messages
  WHERE account_id = :account_id
    AND sender_type = 'Captain::Assistant'
    AND sender_id   = :assistant_id
    AND created_at BETWEEN :start AND :end
)
SELECT
  COUNT(DISTINCT re.conversation_id)::float
    / NULLIF((SELECT COUNT(*) FROM handled), 0) AS handoff_rate
FROM reporting_events re
JOIN handled h ON h.conversation_id = re.conversation_id
WHERE re.account_id = :account_id
  AND re.name IN ('conversation_captain_inference_handoff',
                  'conversation_bot_handoff');
```

## Median First-Response Time

Definition: How fast Captain gives the customer its first real (public, outgoing) reply after
the conversation starts. Usually near-instant — a strong UX selling point and a good way to
spot a misconfigured/slow assistant.

```sql
SELECT
  percentile_cont(0.5) WITHIN GROUP (ORDER BY first_resp_secs) AS median_secs,
  AVG(first_resp_secs)                                          AS avg_secs
FROM (
  SELECT c.id,
         EXTRACT(EPOCH FROM (MIN(m.created_at) - c.created_at)) AS first_resp_secs
  FROM conversations c
  JOIN messages m
    ON m.conversation_id = c.id
   AND m.sender_type = 'Captain::Assistant'
   AND m.sender_id   = :assistant_id
   AND m.message_type = 1        -- outgoing
   AND m.private = false
  WHERE c.account_id = :account_id
    AND c.created_at BETWEEN :start AND :end
  GROUP BY c.id, c.created_at
) t;
```

## Reopen-After-Auto-Resolve Rate (premature closures)

Definition: Of the conversations Captain auto-resolved, the share that got reopened afterwards.
A quality/over-eagerness signal — high values mean Captain is closing tickets the customer
wasn't actually done with. (`conversation_opened` with `value > 0` is a reopen, not the first
open.)

```sql
WITH resolved AS (
  SELECT DISTINCT re.conversation_id
  FROM reporting_events re
  JOIN captain_inboxes ci ON ci.inbox_id = re.inbox_id
  WHERE re.account_id = :account_id
    AND ci.captain_assistant_id = :assistant_id
    AND re.name = 'conversation_captain_inference_resolved'
    AND re.created_at BETWEEN :start AND :end
)
SELECT
  COUNT(DISTINCT o.conversation_id)::float
    / NULLIF((SELECT COUNT(*) FROM resolved), 0) AS reopen_rate
FROM reporting_events o
JOIN resolved r ON r.conversation_id = o.conversation_id
WHERE o.account_id = :account_id
  AND o.name = 'conversation_opened'
  AND o.value > 0;
```

## Flagged-Response Rate

Definition: How often human agents reported a Captain message as bad
(`captain_message_reports`), as a share of the public answers Captain produced. A direct
human-in-the-loop quality score — rising values mean agents are losing trust in the answers.

```sql
WITH captain_msgs AS (
  SELECT id
  FROM messages
  WHERE account_id = :account_id
    AND sender_type = 'Captain::Assistant'
    AND sender_id   = :assistant_id
    AND message_type = 1
    AND private = false
    AND created_at BETWEEN :start AND :end
)
SELECT
  (SELECT COUNT(*) FROM captain_message_reports r
     WHERE r.message_id IN (SELECT id FROM captain_msgs))::float
  / NULLIF((SELECT COUNT(*) FROM captain_msgs), 0) AS flagged_rate;
```

## Conversation Depth (messages per handled conversation)

Definition: Average number of public replies Captain sends per conversation it handles. Low
(~1) = quick one-shot answers; high = Captain is grinding through long back-and-forths, which
often correlates with the cases it ends up handing off.

```sql
SELECT
  COUNT(*)::float / NULLIF(COUNT(DISTINCT conversation_id), 0) AS msgs_per_conversation
FROM messages
WHERE account_id = :account_id
  AND sender_type = 'Captain::Assistant'
  AND sender_id   = :assistant_id
  AND message_type = 1
  AND private = false
  AND created_at BETWEEN :start AND :end;
```

## Knowledge Base Coverage

Definition: How much knowledge backs this assistant — approved vs. still-pending FAQ responses,
plus synced documents. Not a performance metric but the leading indicator: thin/low-approval
knowledge usually explains a low deflection rate. (Time-independent; it's the assistant's
current state.)

```sql
SELECT
  COUNT(*) FILTER (WHERE status = 1) AS approved_responses,
  COUNT(*) FILTER (WHERE status = 0) AS pending_responses,
  (SELECT COUNT(*) FROM captain_documents d
     WHERE d.assistant_id = :assistant_id) AS documents
FROM captain_assistant_responses
WHERE assistant_id = :assistant_id;
```

---

## Notes for building the overview page

- **Two attribution paths exist** and answer slightly different questions. Message-based
  (`sender_id = assistant`) = "conversations Captain actually engaged." Inbox-based
  (`captain_inboxes`) = "conversations that flowed through Captain's inbox, engaged or not."
  Message-based is used for the handled/rate metrics (tighter); inbox-based only for the reopen
  metric since `inference_resolved` is emitted by the auto-resolve job. If an inbox has exactly
  one assistant, the two converge.
- **`reporting_events` has no `assistant_id`** — everything is joined back through
  `conversation_id` or `inbox_id`. Fine today, but multi-assistant-per-inbox support would want
  assistant attribution stamped on the event at write time.
- **`value` on the captain inference events** is "seconds from conversation creation to the
  event" (see `create_captain_inference_event`), so time-to-resolve / time-to-handoff are
  almost free if you want a couple more timing metrics.
