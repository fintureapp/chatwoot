# Proposal: Actor Attribution for Captain Reporting

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

The existing reporting pipeline gets part of the way there, but it was built around generic conversation metrics. Captain reporting needs stronger attribution: for each reporting event, we need to know who performed or caused the event.

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

## Proposed Change

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

## Metrics Enabled By This Change

### Captain-Handled Conversations

Primary definition:

- Conversations with at least one public outgoing message from `Captain::Assistant`.

This still comes from messages because participation is message-level behavior, not only an outcome event.

### Captain-Resolved Conversations

Definition:

- Conversations with a resolution reporting event caused by `Captain::Assistant`.

This should include Captain resolution paths that currently produce generic resolve events.

### Resolved Without Human Help

Definition:

- Captain-involved conversation.
- Resolved by `Captain::Assistant`.
- No public outgoing `User` message before the Captain resolution event.

This answers whether Captain deflected the conversation without human participation.

### Handoff Rate

Definition:

- Captain handoff events divided by Captain-handled conversations.

With actor attribution:

```ruby
conversation_bot_handoff where actor_type = 'Captain::Assistant'
```

This avoids mixing Captain handoffs with AgentBot or other bot handoffs.

### CSAT For Captain-Involved Conversations

Definition:

- `csat_survey_responses` joined to conversations where Captain participated.

CSAT still belongs in the CSAT table. Actor attribution does not replace CSAT storage, but it makes the Captain cohort cleaner.

### CSAT: Captain-Involved vs Human-Only

Definitions:

- Captain-involved: conversations with Captain participation or Captain actor events.
- Human-only: conversations with no Captain participation and no Captain actor events.

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

CSAT trends continue to come from `csat_survey_responses`, using the Captain-involved cohort.

## Implementation Notes

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

## Expected Outcome

Adding `actor_type` and `actor_id` gives Captain reporting a durable attribution layer while preserving the generic reporting pipeline.

It does not require turning `reporting_events` into a Captain-only analytics table. It simply makes each event answer one missing question:

```text
Who caused this?
```

That is the key missing piece for reliable Captain value reporting.
