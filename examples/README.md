# Jev examples

Each scenario matches a [Jev use case](https://jevtypesafeai.com/use-cases). Every CSV row is sent to Jev as a JSON object (column name → string value).

Requires `TYPESAFE_API_KEY` in the environment (or `.env` when using `just`).

## Support triage (choice)

Routes inbound support messages to a team.

```bash
scala-cli run . -- --input examples/support-triage.csv
```

Writes `examples/support-triage-out.csv` using `examples/support-triage.yaml`. Override paths with `--config` and `--output` if needed.

Output columns appended: `department_choice`, `department_confidence`, `jev_error`.

## Content moderation (noul)

Estimates whether UGC should be blocked.

```bash
scala-cli run . -- --input examples/content-moderation.csv
```

Output columns: `should_block_probability`, `jev_error`.

## Lead scoring (score)

Scores sales readiness on a cold / warm / hot scale.

```bash
scala-cli run . -- --input examples/lead-scoring.csv
```

Output columns: `sales_readiness_score`, `sales_readiness_nearest_label`, `jev_error`.

Or use convenience recipes from the repo root: `just example-triage`, `just example-moderation`, `just example-lead-scoring`.
