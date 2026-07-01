# Proposal: Captain Reporting Attribution and Fact Table

## Context

Captain reporting needs to answer customer-facing questions about the value Captain creates:

- How many conversations did Captain handle or participate in?
- How many Captain-involved conversations were resolved without human help?
- How often did Captain hand off to a human agent?
- Are customers satisfied with Captain-involved conversations?
- How does CSAT compare between Captain-involved and human-only conversations?
- How much human support time did Captain likely save?
- Can we estimate cost or time saved from conversations handled or deflected by Captain?
- How are Captain resolution, handoff, CSAT, and estimated time-saved metrics trending?

The existing reporting pipeline gets part of the way there, but it was built around generic conversation metrics. Captain reporting needs two lightweight improvements:

- Stronger attribution: for each reporting event, we need to know who performed or caused the event.
- A small Captain-specific fact table: for each Captain-involved conversation, we need durable milestone timestamps and CSAT fields that are annoying or expensive to recompute repeatedly.

## Current System

Chatwoot currently stores operational reporting rows in `reporting_events`. These rows capture:

- Event name, such as `conversation_resolved`, `conversation_bot_resolved`, `conversation_bot_handoff`, `first_response`, `reply_time`, and `conversation_opened`.
- Event value, usually a duration in seconds.
- Account, inbox, user, and conversation references.
- Event start and end timestamps.

Captain-specific reporting currently depends on a combination of sources:

- Captain-authored messages identify conversations where Captain participated.
- `reporting_events` identify generic resolution, handoff, reopen, first response, and reply-time events.
- `csat_survey_responses` stores customer satisfaction ratings.
- Captain knowledge tables store assistant response and document coverage.

This means Captain stats are currently inferred rather than directly attributed.

## Why The Current System Does Not Cut It

The main gap is that `reporting_events` does not clearly identify the actor behind an event.

For example, `conversation_bot_handoff` only tells us that a bot handoff happened. It does not tell us whether the handoff was caused by:

- Captain
- A legacy `AgentBot`
- Another bot integration
- A system or automation path

Similarly, `conversation_bot_resolved` means a conversation was resolved in an active bot inbox without a human outgoing message. That is useful, but it is still not the same as saying Captain resolved the conversation. Today we have to intersect that event with Captain-authored messages to infer Captain involvement.

This creates several problems:

- Attribution is indirect and harder to explain.
- Different bot systems are mixed together under generic bot events.
- Queries become more complex because they must join reporting events, messages, CSAT, and Captain tables.
- Historical interpretation can drift when conversation assignment, inbox configuration, or message patterns change later.
- Customer-facing metrics need a stronger foundation than best-effort inference.

The current system can support directional Captain reporting, but it is not ideal for defensible customer-facing value metrics.

## Proposed Change 1: Reporting Event Actor Attribution

Add actor attribution columns to `reporting_events`:

```ruby
actor_type :string
actor_id   :bigint
```

The actor should represent the entity that performed or caused the reporting event.

Examples:

| Event | actor_type | actor_id |
|---|---|---|
| Human agent resolves conversation | `User` | agent id |
| Captain resolves conversation | `Captain::Assistant` | assistant id |
| Captain hands off conversation | `Captain::Assistant` | assistant id |
| AgentBot hands off conversation | `AgentBot` | agent bot id |
| Automation resolves conversation | `AutomationRule` | automation rule id |

This should be additive. The existing `user_id` column should remain unchanged because it is already used as a report dimension and does not consistently mean "the actor who caused the event".

## Why The Actor Model Works

The actor model makes attribution explicit at the point where the reporting event is created.

Instead of asking, "Did this generic bot event involve Captain based on nearby messages?", we can ask:

```ruby
ReportingEvent.where(
  name: 'conversation_bot_handoff',
  actor_type: 'Captain::Assistant',
  actor_id: assistant.id
)
```

That gives us a direct and explainable source for Captain-caused actions.

It also keeps the reporting model generic. The same columns can support humans, Captain, AgentBot, automation, and future actors without adding Captain-only columns to the base reporting table.

The result is cleaner reporting:

- Captain resolution count can come from resolved events where the actor is Captain.
- Captain handoff count can come from handoff events where the actor is Captain.
- Human-only comparisons can exclude conversations with Captain actors.
- AgentBot and Captain metrics no longer collide under generic bot event names.
- Time-series trends can group by event name and actor instead of inferred cohorts.

## Proposed Change 2: Small Captain Conversation Fact Table

Add a small fact table for Captain-involved conversations:

```ruby
captain_conversation_facts

account_id
conversation_id
assistant_id
inbox_id

first_captain_message_at
last_captain_message_at

captain_resolved_at
captain_handed_off_at
first_human_reply_after_captain_at
reopened_after_captain_resolution_at

csat_response_id
csat_rating
csat_submitted_at

created_at
updated_at
```

This table should be intentionally sparse. It should not become a full aggregate table, and it should not duplicate every message count or reporting event. Its job is to make the Captain conversation cohort and key lifecycle milestones cheap, stable, and explainable.

Recommended constraints and indexes:

```ruby
unique index on conversation_id
index on [account_id, assistant_id, first_captain_message_at]
index on [account_id, captain_resolved_at]
index on [account_id, captain_handed_off_at]
index on [account_id, csat_submitted_at]
```

`csat_response_id` should point back to `csat_survey_responses`. The fact table should store `csat_rating` and `csat_submitted_at` for dashboard queries, but the free-text feedback should remain in `csat_survey_responses`.

## Why The Fact Table Should Stay Small

A larger fact table with reply counters, duration counters, cost estimates, and many derived fields would be expensive to maintain and easy to make inconsistent.

The useful middle ground is a sparse milestone table:

- Most fields are set once.
- Repeated updates are limited to `last_captain_message_at`.
- Counts can still be derived from `messages`, `reporting_events`, and `csat_survey_responses` when needed.
- The Captain cohort becomes a simple table lookup instead of repeated message/event inference.

This keeps write complexity low while making read paths much cleaner.

## Metrics Enabled By This Change

### Captain-Handled Conversations

Primary definition:

- Rows in `captain_conversation_facts`.

The fact row is created when Captain first sends a public message in the conversation. `first_captain_message_at` and `last_captain_message_at` define the participation window.

### Captain-Resolved Conversations

Definition:

- Rows where `captain_resolved_at` is present.

This field is populated from resolution reporting events where `actor_type = 'Captain::Assistant'`.

### Resolved Without Human Help

Definition:

- Captain-involved conversation.
- `captain_resolved_at` is present.
- No public outgoing `User` message before the Captain resolution event.

This answers whether Captain deflected the conversation without human participation.

### Handoff Rate

Definition:

- Rows where `captain_handed_off_at` is present divided by total Captain fact rows.

`captain_handed_off_at` is populated from handoff reporting events where `actor_type = 'Captain::Assistant'`, avoiding collisions with AgentBot or other bot handoffs.

### CSAT For Captain-Involved Conversations

Definition:

- Captain fact rows where `csat_rating` is present.

CSAT still belongs in `csat_survey_responses`, but copying `csat_response_id`, `csat_rating`, and `csat_submitted_at` into the fact table makes Captain CSAT reporting simple.

### CSAT: Captain-Involved vs Human-Only

Definitions:

- Captain-involved: conversations with a row in `captain_conversation_facts`.
- Human-only: conversations without a Captain fact row.

This allows customer-facing comparison between conversations where Captain helped and conversations handled only by humans.

### Estimated Time Saved

Definition:

- Estimated saved time based on Captain-handled or Captain-deflected work.

Possible calculation:

```text
Captain public replies * average human reply time
```

or:

```text
Captain-resolved-without-human conversations * average human handling time
```

The actor model does not define the estimation formula by itself, but it gives the formula better inputs by identifying which resolutions and handoffs were actually caused by Captain.

The fact table provides the reusable Captain cohort for these estimates. Reply counts and average human reply time can still be queried from source tables.

### Estimated Cost Saved

Definition:

```text
estimated_time_saved * configured_support_cost_per_hour
```

This can be derived from time-saved estimates. The actor model improves the reliability of the deflection and resolution counts that feed the estimate.

### Trends

Metrics can be trended over time by grouping `reporting_events` by date and filtering on actor:

- Captain resolution trend
- Captain handoff trend
- Captain reopen trend
- Captain deflection trend
- Human-only comparison trend

CSAT trends can come directly from fact rows with `csat_submitted_at`.

## Implementation Notes: Actor Attribution

When dispatching events, Chatwoot already passes `performed_by` in several paths. Reporting event creation should use that object to populate:

- `actor_type = performed_by.class.name`
- `actor_id = performed_by.id`

For message-derived events, the message sender can be used when appropriate:

- `first_response`
- `reply_time`

For conversation status events, `performed_by` should be preferred when present. This is important for Captain because Captain jobs set `Current.executed_by` before resolving or handing off conversations.

Backfill can be partial:

- Captain-authored messages can identify Captain-involved conversations.
- Existing generic bot events can sometimes be attributed to Captain when the conversation has Captain messages.
- Events without clear historical actor evidence should remain null rather than guessed.

## Implementation Notes: Captain Fact Table

The fact table should be updated from existing lifecycle points:

- Captain public message created:
  - Find or create the fact row.
  - Set `first_captain_message_at` if blank.
  - Update `last_captain_message_at`.
- Captain resolves conversation:
  - Set `captain_resolved_at` if blank.
- Captain hands off conversation:
  - Set `captain_handed_off_at` if blank.
- Human public reply after Captain participation:
  - Set `first_human_reply_after_captain_at` if blank.
- Conversation opens after Captain resolution:
  - Set `reopened_after_captain_resolution_at` if blank.
- CSAT response created or updated:
  - If a fact row exists for the conversation, set `csat_response_id`, `csat_rating`, and `csat_submitted_at`.

The fact updater should be idempotent. It should prefer setting first-occurrence fields only when blank, except for `last_captain_message_at` and CSAT fields, which can be updated.

## Expected Outcome

Adding `actor_type` and `actor_id` gives Captain reporting a durable attribution layer while preserving the generic reporting pipeline.

It does not require turning `reporting_events` into a Captain-only analytics table. It simply makes each event answer one missing question:

```text
Who caused this?
```

Adding `captain_conversation_facts` then gives dashboards a small, stable Captain conversation cohort with the most important milestone and CSAT fields.

Together, these changes keep the raw event pipeline generic while giving Captain reporting enough structure to answer customer-facing value questions without repeated fragile inference.
