# jevvy YAML configuration reference

jevvy runs each row of a CSV through [Jev](https://docs.typesafe.ai/) using questions defined in a YAML file. This document specifies that format: fields, validation, how settings combine with the CLI and environment, and how results appear in the output CSV.

For *what* to ask Jev and how to phrase judgments, see [TypeSafe documentation](https://docs.typesafe.ai/) and the [Jev use cases](https://jevtypesafeai.com/use-cases). This reference covers *how* jevvy reads YAML and wires it to batch processing.

## How the config file is chosen

By default, jevvy looks for a YAML file next to your input CSV:

| Input CSV | Default config |
|-----------|----------------|
| `myfile.csv` | `myfile.yaml` |
| `examples/support-triage.csv` | `examples/support-triage.yaml` |

Override with `--config`:

```bash
jevvy --input data/leads.csv --config configs/lead-scoring.yaml
```

Output defaults to `{input-stem}-out.csv` (for example `myfile-out.csv`). Override with `--output`.

## Data flow

For each row:

1. CSV columns become a JSON **state** object (all values are strings).
2. Every question in `questions` is sent in one Jev request with that state.
3. jevvy appends answer columns (and `jev_error`) to the row and writes the output CSV.

## Top-level fields

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `questions` | list of question objects | **Yes** | — | Must contain at least one question. |
| `concurrency` | integer | No | `1` | Parallel rows in flight. Must be ≥ 1. |
| `delay_ms` | integer (milliseconds) | No | `0` | Sleep before each row after the first (rate limiting). Must be ≥ 0. |
| `max_retries` | integer | No | `3` | Extra Jev HTTP attempts after the first on transient failures (429, 529, 5xx, connection). `0` disables retries. See [Max retries precedence](#max-retries). |
| `model` | string | No | from env | Jev model name; see [Model precedence](#model-precedence). |
| `timeout_seconds` | integer | No | SDK default | Per-request HTTP timeout for Jev. |

### Minimal config

Only `questions` is required:

```yaml
questions:
  - name: is_spam
    type: noul
    question: Is this message spam?
```

### Full top-level example

```yaml
model: jev-latest
timeout_seconds: 60
concurrency: 4
delay_ms: 250
max_retries: 3

questions:
  - name: should_block
    type: noul
    question: Should this content be blocked?
```

YAML comments (`#`) are ignored by the parser and are useful for documenting intent:

```yaml
# Content moderation batch — see examples/content-moderation.csv
concurrency: 2

questions:
  - name: should_block
    type: noul
    question: Should this user-generated content be blocked before publication?
```

## CLI and environment overrides

Some settings can be overridden outside YAML.

### Concurrency

| Priority (highest first) | Source |
|--------------------------|--------|
| 1 | CLI `--concurrency N` |
| 2 | YAML `concurrency` |
| 3 | Default `1` |

Example: YAML says `concurrency: 4`, but a one-off dry run uses a single worker:

```bash
jevvy --input myfile.csv --concurrency 1
```

### Max retries

Transient Jev API failures are retried inside each row’s request via [jev-nim-client](https://github.com/aboisvert/jev-nim-client) (`RetryPolicy`). Defaults match the Scala tool: exponential backoff from 500 ms (cap 8 s, jitter), honoring `Retry-After` on 429 when present. Validation errors (422) and auth failures are not retried.

| Priority (highest first) | Source |
|--------------------------|--------|
| 1 | CLI `--max-retries N` |
| 2 | YAML `max_retries` |
| 3 | Default `3` |

Use `max_retries: 0` (or `--max-retries 0`) to fail fast on the first error — useful for debugging. For rate limits across many rows, combine a lower `concurrency` or non-zero `delay_ms` with retries rather than disabling retries entirely.

Example:

```bash
jevvy --input myfile.csv --max-retries 0
```

### Model precedence

| Priority (highest first) | Source |
|--------------------------|--------|
| 1 | CLI `--model NAME` |
| 2 | YAML `model` |
| 3 | Environment `TYPESAFE_DEFAULT_MODEL` |
| 4 | SDK default `jev-latest` |

Example YAML:

```yaml
model: yaml-model

questions:
  - name: is_spam
    type: noul
    question: Is this spam?
```

```bash
# Uses cli-model, not yaml-model
jevvy --input myfile.csv --model cli-model
```

API key and base URL are **not** in YAML; set `TYPESAFE_API_KEY` (required) and optionally `TYPESAFE_BASE_URL`. See the [README](../README.md#environment-variables).

### Timeout, delay, and retries

- `timeout_seconds` — YAML only (applied when the config is loaded).
- `delay_ms` — YAML only; applied between row requests (row index 0 has no delay).
- `max_retries` — YAML or CLI; see [Max retries](#max-retries). Retries apply per row’s Jev call, not between rows.

## Question object (all types)

Every entry under `questions` is a mapping with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Stable identifier for Jev and for **output column names**. Use `snake_case`. |
| `type` | string | Yes | One of `noul`, `choice`, `score` (case-insensitive; surrounding whitespace is trimmed). |
| `question` | string | Yes | Natural-language question Jev answers about each row’s state. |
| `options` | list | For `choice` only | Non-empty list of `{ id, description }`. |
| `levels` | list | For `score` only | At least two `{ label, description }` entries. |

**Authoring tip:** Keep each `name` unique within a file. jevvy does not currently reject duplicates, but duplicate names would produce duplicate output headers and ambiguous Jev question ids.

### Question types at a glance

| `type` | Jev primitive | Typical use |
|--------|---------------|-------------|
| `noul` | Yes/no probability | Gate, flag, moderate (block / allow). |
| `choice` | Pick one option | Routing, classification, taxonomy. |
| `score` | Position on a scale | Ranking, readiness, severity bands. |

---

## Type: `noul`

A **noul** question asks whether something is true. Jev returns a calibrated probability in `[0, 1]`, not a raw boolean. Your application chooses thresholds (for example “block if probability > 0.85”).

### Minimal noul

```yaml
questions:
  - name: is_spam
    type: noul
    question: Is this message spam?
```

### Content moderation (bundled example)

Matches [examples/content-moderation.yaml](../examples/content-moderation.yaml):

```yaml
concurrency: 2

questions:
  - name: should_block
    type: noul
    question: Should this user-generated content be blocked before publication?
```

**Output columns:** `should_block_probability`, then `jev_error`.

### Noul with batch tuning

```yaml
concurrency: 3
delay_ms: 500
timeout_seconds: 90

questions:
  - name: needs_human_review
    type: noul
    question: Does this support ticket need escalation to a human agent?
```

### Case-insensitive type

These are equivalent:

```yaml
questions:
  - name: is_urgent
    type: NOUL
    question: Does this convey urgency?
```

```yaml
questions:
  - name: is_urgent
    type: "  noul  "
    question: Does this convey urgency?
```

---

## Type: `choice`

A **choice** question asks which option best applies. Each option has:

- **`id`** — Stable machine value; this is what appears in `{name}_choice` in the output CSV.
- **`description`** — Human-readable context for Jev (payments, bugs, and so on).

Under the hood, jevvy builds `ChoiceOption(id, id, description)` — the same string is used as the option key and the exported choice value.

### Minimal choice

```yaml
questions:
  - name: department
    type: choice
    question: Which team?
    options:
      - id: billing
        description: Payments
      - id: technical
        description: Bugs
```

### Support triage (bundled example)

Matches [examples/support-triage.yaml](../examples/support-triage.yaml):

```yaml
concurrency: 2
delay_ms: 0

questions:
  - name: department
    type: choice
    question: Which team should handle this inbound support message?
    options:
      - id: billing
        description: Payments, invoicing, refunds, payout failures
      - id: technical
        description: Bugs, outages, API errors, integrations
      - id: account
        description: Login, access, permissions, account settings
```

**Output columns:** `department_choice`, `department_confidence`, `jev_error`.

### Many options (stable ids)

Prefer short, stable `id` values and put detail in `description`:

```yaml
questions:
  - name: product_area
    type: choice
    question: Which product area is this feedback about?
    options:
      - id: mobile_app
        description: iOS or Android client issues and UX
      - id: web_dashboard
        description: Browser-based admin and reporting UI
      - id: public_api
        description: REST or GraphQL integrations, webhooks, rate limits
      - id: billing
        description: Subscriptions, invoices, payment methods
      - id: other
        description: Does not clearly fit the categories above
```

### Choice without `options` (invalid)

Missing or empty `options` fails when the config is built:

```yaml
# INVALID — will error: choice question 'department' requires non-empty options
questions:
  - name: department
    type: choice
    question: Which team?
    options: []
```

---

## Type: `score`

A **score** question places the row on an ordered scale defined by **levels**. You need at least two levels. Each level has:

- **`label`** — Short name (for example `cold`, `warm`, `hot`); used in `{name}_nearest_label`.
- **`description`** — What that level means for Jev.

jevvy sends each level to Jev as the text `"label: description"`. The model can return a numeric score that sits *between* levels; jevvy exports `{name}_score` (four decimal places) and `{name}_nearest_label`.

### Minimal score (two levels)

```yaml
questions:
  - name: readiness
    type: score
    question: How ready is this lead?
    levels:
      - label: cold
        description: Low intent
      - label: hot
        description: High intent
```

### Lead scoring (bundled example)

Matches [examples/lead-scoring.yaml](../examples/lead-scoring.yaml):

```yaml
concurrency: 2

questions:
  - name: sales_readiness
    type: score
    question: How sales-ready is this inbound lead?
    levels:
      - label: cold
        description: Low intent, vague interest, unlikely to buy soon
      - label: warm
        description: Real problem and budget signals, evaluating options
      - label: hot
        description: Strong fit, urgency, decision-maker engaged
```

**Output columns:** `sales_readiness_score`, `sales_readiness_nearest_label`, `jev_error`.

### Severity scale (four levels)

```yaml
questions:
  - name: incident_severity
    type: score
    question: How severe is this reported incident?
    levels:
      - label: low
        description: Minor inconvenience, workaround available
      - label: medium
        description: Feature degraded for some users
      - label: high
        description: Major feature down or data at risk
      - label: critical
        description: Full outage or active security incident
```

### Score with one level (invalid)

```yaml
# INVALID — will error: score question 'readiness' requires at least 2 levels
questions:
  - name: readiness
    type: score
    question: How ready?
    levels:
      - label: cold
        description: Low
```

---

## Multiple questions in one file

A single config may define several questions. jevvy sends **all** of them in **one** Jev request per CSV row. Output columns are appended in config order, then `jev_error`.

### Noul gate + choice route

Useful when you want both a probability and a routing label in one pass:

```yaml
concurrency: 2

questions:
  - name: is_abusive
    type: noul
    question: Does this message contain abusive or harassing language?

  - name: queue
    type: choice
    question: Which internal queue should handle this ticket?
    options:
      - id: trust_safety
        description: Policy violations, harassment, illegal content
      - id: general_support
        description: Standard product and billing help
      - id: engineering
        description: Defects, outages, integration failures
```

**Example output headers** (input columns omitted):

```text
is_abusive_probability,queue_choice,queue_confidence,jev_error
```

### All three primitives together

```yaml
model: jev-latest
concurrency: 1

questions:
  - name: is_urgent
    type: noul
    question: Does this request require same-day response?

  - name: department
    type: choice
    question: Which team should own this?
    options:
      - id: billing
        description: Invoices and payments
      - id: technical
        description: Bugs and API issues

  - name: frustration
    type: score
    question: How frustrated does the customer seem?
    levels:
      - label: calm
        description: Neutral or polite tone
      - label: annoyed
        description: Impatience or repeated follow-ups
      - label: angry
        description: Threats, all-caps, or churn language
```

**Example output headers:**

```text
is_urgent_probability,department_choice,department_confidence,frustration_score,frustration_nearest_label,jev_error
```

Question order in YAML is preserved in the output column order.

---

## CSV input and Jev state

jevvy does **not** map CSV columns in YAML. Every header in the input CSV becomes a field in the JSON state for that row. The question text should refer to the kind of data you put in the sheet (for example “this inbound support message”), and Jev sees whatever columns you provide.

### Example row

From [examples/support-triage.csv](../examples/support-triage.csv):

```csv
subject,body,customer_tier,channel
Payouts failing again,"Help! My payouts have been failing for 3 days...",pro,email
```

### Implied state (conceptual)

Fields are built as string values; keys are sorted alphabetically when encoding (order does not affect Jev):

```json
{
  "body": "Help! My payouts have been failing for 3 days...",
  "channel": "email",
  "customer_tier": "pro",
  "subject": "Payouts failing again"
}
```

Design CSV columns so the model has the context your `question` strings assume (`body`, `subject`, `tier`, attachments metadata, and so on).

---

## Output CSV columns

jevvy keeps all input columns unchanged, then appends columns derived from each question’s `name`, then **`jev_error`**.

| Question type | Appended columns | Format |
|---------------|------------------|--------|
| `noul` | `{name}_probability` | Probability, 4 decimal places (e.g. `0.7500`) |
| `choice` | `{name}_choice`, `{name}_confidence` | Selected `id`, then confidence (4 decimal places) |
| `score` | `{name}_score`, `{name}_nearest_label` | Numeric score (4 decimal places), then nearest level `label` |

### `jev_error`

- Empty string on success.
- Non-empty on API errors, missing answers in the response, or other row-level failures. Other answer cells for that row are blank.

Example successful row (input + answers):

```text
subject,body,customer_tier,channel,department_choice,department_confidence,jev_error
Payouts failing again,"Help!...",pro,email,billing,0.9100,
```

Example failed row:

```text
...,technical,,rate limited
```

The process exits with code **1** if any row has a non-empty `jev_error` or if config/IO fails.

---

## Validation and error messages

Errors surface when loading or resolving the config (before or at startup) or per row at runtime.

### Config load / build (`questions`)

| Condition | Typical message |
|-----------|-----------------|
| Empty `questions: []` | `config must define at least one question` |
| Unknown `type` | `question 'x' has unknown type 'magic' (expected noul, choice, or score)` |
| `choice` with no options | `choice question 'department' requires non-empty options` |
| `score` with fewer than 2 levels | `score question 'readiness' requires at least 2 levels` |
| Invalid YAML syntax | `invalid YAML config: ...` |
| Unreadable file | `cannot read config PATH: ...` |

Choice and score questions are also validated with the Jev SDK before run; malformed structures fail at build time with the SDK validation message.

### Resolve (settings)

| Condition | Message |
|-----------|---------|
| `concurrency` < 1 (CLI or YAML) | `concurrency must be at least 1` |
| `delay_ms` < 0 | `delay_ms must be non-negative` |
| `max_retries` < 0 | `max_retries must be non-negative` |
| Missing API key (env) | From `JevConfig.fromEnv` (e.g. missing `TYPESAFE_API_KEY`) |

### Per-row (output)

| Condition | Effect |
|-----------|--------|
| Jev API error | Blank answer columns; `jev_error` set to message |
| Response missing an answer | Blank answer columns; `jev_error` explains missing question |

---

## Authoring checklist

1. **Pair CSV and YAML** — Default config path is `{csv-stem}.yaml`; keep them named together.
2. **Stable `name` values** — They become column headers; avoid spaces and renames after you depend on downstream tools.
3. **Write `question` for the state you send** — Include enough context in CSV columns; the YAML question should match that data.
4. **Choice `id` values** — Use stable snake_case; descriptions can be long and explanatory.
5. **Score level order** — List levels from low to high; labels should match what you want in `{name}_nearest_label`.
6. **Concurrency and `delay_ms`** — Increase parallelism for speed; add delay if you hit rate limits.
7. **`max_retries`** — Leave at the default for production batches; set `0` only when you need immediate failure without backoff.
8. **Model and timeout** — Set `model` / `timeout_seconds` in YAML for reproducible batches; use CLI `--model` for experiments.

---

## Related links

- [README](../README.md) — Quick start, CLI, environment variables
- [examples/README.md](../examples/README.md) — Runnable scenarios and output column names
- [examples/](../examples/) — Full YAML + CSV pairs
- [TypeSafe AI / Jev documentation](https://docs.typesafe.ai/)
- [jev-nim-client](https://github.com/aboisvert/jev-nim-client) — How jevvy calls Jev internally
