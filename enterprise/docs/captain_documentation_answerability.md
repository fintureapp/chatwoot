# Captain Documentation Answerability Handoff

We investigated traces where Captain answered even though documentation search was weak, missing, or unrelated.

## What Failed

The main pattern was not just "no docs found". It was:

> Captain retrieved weak or nearby docs, then answered as if they supported the answer.

We saw three failure types:

- The model did not call `search_documentation`.
- The tool returned loosely related docs.
- The model treated "some result exists" as enough evidence.

## What We Tried First

We first tried a deterministic pgvector distance threshold.

For cosine distance in pgvector:

- Lower is better.
- `0` means very similar.
- Higher values mean less similar.

That failed as a product guardrail. Some useful matches had higher distances, and some bad matches shared enough words to look plausible. A single threshold would need constant tuning across accounts, languages, and writing styles.

We also avoided keyword/stopword rules because they quickly become language-specific and account-specific.

## Current Approach

Search and answerability are now separate.

After `search_documentation` retrieves docs, a small LLM check asks:

> Do these docs answer the latest user question?

It returns only `sufficient` or `insufficient`. It does not write customer-facing copy and does not judge the assistant's draft answer.

The decision is added to the tool output. The final assistant generation then uses it:

- `sufficient`: answer from the retrieved docs.
- `insufficient`: do not answer the factual question; ask a clarifying question or offer handoff.

A post-response backstop still exists for the case where the model never called the documentation tool.

## Next Step

Replay weak-documentation traces against this flow and compare the `sufficient` / `insufficient` decisions with the manually reviewed golden set.

Hybrid or keyword search should be added before the answerability check later. Better retrieval should improve the docs we pass into the same check.
