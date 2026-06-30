# Captain Overview — effective SQL per stat

These are the queries `Captain::AssistantStatsBuilder` effectively runs for
`account_id = 1`, `assistant_id = 1`, over a **30-day current window**
(`created_at >= NOW() - INTERVAL '30 days'`). Each metric runs once for the
current window and once for the previous equal-length window
(`NOW() - INTERVAL '60 days'` to `NOW() - INTERVAL '30 days'`); only the current
window is shown below. Swap the interval bounds for the previous window.

Knowledge stats are point-in-time (no window, no previous).

---

## 1. Conversations handled

Distinct conversations the assistant authored any message in.

```sql
SELECT COUNT(DISTINCT conversation_id)
FROM messages
WHERE account_id = 1
  AND sender_type = 'Captain::Assistant'
  AND sender_id = 1
  AND created_at >= NOW() - INTERVAL '30 days';
```

Indexes that matter: `messages (account_id, ...)`, plus the `sender_type/sender_id`
filter. This is the "handled set" reused as a subquery by stats 2 and 3.

---

## 2 & 3. Auto-resolution rate + handoff rate (combined)

`auto_resolution = resolved / handled * 100` and `handoff = handoff / handled * 100`
share the same handled-set subquery, so they fold into a single pass with
conditional aggregation. This runs the (costly) `messages` handled-set subquery
**once** and scans `reporting_events` once, instead of twice each.

```sql
SELECT
  COUNT(DISTINCT conversation_id)
    FILTER (WHERE name IN ('conversation_captain_inference_resolved',
                           'conversation_bot_resolved'))                AS resolved,
  COUNT(DISTINCT conversation_id)
    FILTER (WHERE name IN ('conversation_captain_inference_handoff',
                           'conversation_bot_handoff'))                 AS handoff
FROM reporting_events
WHERE account_id = 1
  AND name IN ('conversation_captain_inference_resolved', 'conversation_bot_resolved',
               'conversation_captain_inference_handoff', 'conversation_bot_handoff')
  AND conversation_id IN (
    SELECT conversation_id
    FROM messages
    WHERE account_id = 1
      AND sender_type = 'Captain::Assistant'
      AND sender_id = 1
      AND created_at >= NOW() - INTERVAL '30 days'
  );
```

The rates are still computed in Ruby (`resolved / handled`, `handoff / handled`),
so divide-by-zero guarding stays in the builder. The two rates do **not** sum to
100%: a handled conversation may carry neither event (still open) or both
(handed off then later resolved).

Note: the event rows themselves are **not** date-filtered; the window is applied
via the handled-set subquery (the conversations the assistant touched in the
window).

### Optional: fold in "handled" too (one query for all three)

Materialize the handled set once in a CTE and derive all three numbers from it.
Useful because the page also displays `handled`, and every metric runs for both
the current and previous window.

```sql
WITH handled AS (
  SELECT DISTINCT conversation_id
  FROM messages
  WHERE account_id = 1
    AND sender_type = 'Captain::Assistant'
    AND sender_id = 1
    AND created_at >= NOW() - INTERVAL '30 days'
)
SELECT
  (SELECT COUNT(*) FROM handled) AS handled,
  COUNT(DISTINCT re.conversation_id)
    FILTER (WHERE re.name IN ('conversation_captain_inference_resolved',
                              'conversation_bot_resolved'))             AS resolved,
  COUNT(DISTINCT re.conversation_id)
    FILTER (WHERE re.name IN ('conversation_captain_inference_handoff',
                              'conversation_bot_handoff'))              AS handoff
FROM reporting_events re
JOIN handled h ON h.conversation_id = re.conversation_id
WHERE re.account_id = 1
  AND re.name IN ('conversation_captain_inference_resolved', 'conversation_bot_resolved',
                  'conversation_captain_inference_handoff', 'conversation_bot_handoff');
```

Keep `handled` sourced from the CTE count (not `COUNT(*)` over the join), so
conversations with no event row still count toward `handled`.

---

## 4. Hours saved

`public_outgoing_count * avg_reply_time_seconds / 3600`, rounded. Two queries.

Public outgoing replies the assistant sent:

```sql
SELECT COUNT(*)
FROM messages
WHERE account_id = 1
  AND sender_type = 'Captain::Assistant'
  AND sender_id = 1
  AND message_type = 1   -- outgoing
  AND private = false
  AND created_at >= NOW() - INTERVAL '30 days';
```

Average reply time across the account in the window (seconds):

```sql
SELECT AVG(value)
FROM reporting_events
WHERE account_id = 1
  AND name = 'reply_time'
  AND created_at >= NOW() - INTERVAL '30 days';
```

---

## 5. Conversation depth (messages / conversation)

`public_outgoing_count / distinct_conversations`. Reuses query 4's count plus:

```sql
SELECT COUNT(DISTINCT conversation_id)
FROM messages
WHERE account_id = 1
  AND sender_type = 'Captain::Assistant'
  AND sender_id = 1
  AND message_type = 1   -- outgoing
  AND private = false
  AND created_at >= NOW() - INTERVAL '30 days';
```

---

## 6. Reopen-after-resolve rate

`reopened / resolved * 100`, where "resolved" is the inbox-based Captain-resolved
set. Two queries.

Resolved (inbox-scoped) in the window:

```sql
SELECT COUNT(DISTINCT conversation_id)
FROM reporting_events
WHERE account_id = 1
  AND name = 'conversation_captain_inference_resolved'
  AND inbox_id IN (
    SELECT inbox_id FROM captain_inboxes WHERE captain_assistant_id = 1
  )
  AND created_at >= NOW() - INTERVAL '30 days';
```

Of those, the ones later reopened (`conversation_opened` with `value > 0`):

```sql
SELECT COUNT(DISTINCT conversation_id)
FROM reporting_events
WHERE account_id = 1
  AND name = 'conversation_opened'
  AND value > 0
  AND conversation_id IN (
    SELECT conversation_id
    FROM reporting_events
    WHERE account_id = 1
      AND name = 'conversation_captain_inference_resolved'
      AND inbox_id IN (
        SELECT inbox_id FROM captain_inboxes WHERE captain_assistant_id = 1
      )
      AND created_at >= NOW() - INTERVAL '30 days'
  );
```

Note: the `conversation_opened` events are **not** date-filtered; a reopen counts
whenever it happened, as long as the resolve fell in the window.

---

## 7. Knowledge (point-in-time, no window)

Approved / pending FAQ counts:

```sql
SELECT status, COUNT(*)
FROM captain_assistant_responses
WHERE assistant_id = 1
GROUP BY status;
-- status: 0 = pending, 1 = approved
```

Document count:

```sql
SELECT COUNT(*)
FROM captain_documents
WHERE assistant_id = 1;
```

`coverage = approved / (approved + pending) * 100`, computed in Ruby.
