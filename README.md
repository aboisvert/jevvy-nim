# jevvy

Run CSV rows through [Jev](https://docs.typesafe.ai/) with YAML-defined questions. Each row becomes JSON state sent to the TypeSafe API; results are written as extra CSV columns.

Licensed under the [Apache License, Version 2.0](LICENSE).

## Usage Requirements

- **`jevvy`** binary (build from source or a release artifact under `out/`)
- **`TYPESAFE_API_KEY`** from your [TypeSafe.ai](https://typesafe.ai) account

## Download

Download MacOS/Linux binaries from the [releases](releases) page.

## Quick Start

Create `myfile.yaml` (see [Configuration](#configuration)), export your API key, and run:

```bash
export TYPESAFE_API_KEY=your-key-here
jevvy --input myfile.csv
```

## CLI Usage

```text
jevvy --input PATH [--config PATH] [--output PATH] [--concurrency N] [--model NAME] [--max-retries N]
```

| Flag | Description |
|------|-------------|
| `--input` | Input CSV path (required) |
| `--config` | YAML config (default: `{input stem}.yaml`) |
| `--output` | Output CSV (default: `{input stem}-out.csv`) |
| `--concurrency` | Override YAML `concurrency` (in-flight HTTP requests) |
| `--model` | Override YAML `model` |
| `--max-retries` | Override YAML `max_retries` (`0` disables retries on transient API errors) |

**Row order:** Output keeps input order. With `concurrency` > 1, Jev calls overlap, but rows are written in FIFO order.

**Retries:** Per-row Jev calls retry transient failures (429, 529, 5xx, connection errors) with exponential backoff (defaults match the Scala tool: 3 retries, 500 ms initial delay, 8 s cap). Tune with YAML `max_retries` or `--max-retries`. The Nim client applies a slightly different jitter shape than the Scala SDK; behavior is otherwise aligned.

Exit code **1** if any row fails or config/IO errors occur.

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TYPESAFE_API_KEY` | API key from your [TypeSafe](https://docs.typesafe.ai/) account | *(required)* |
| `TYPESAFE_BASE_URL` | TypeSafe API base URL | `https://api.typesafe.ai` |
| `TYPESAFE_DEFAULT_MODEL` | Default model when YAML `model` and `--model` are unset | `jev-latest` |

## Configuration

YAML defines batch settings and Jev questions (`noul`, `choice`, `score`). See **[docs/yaml-configuration.md](docs/yaml-configuration.md)**.

Runnable configs: [`examples/`](examples/).

## Examples

| Scenario | Type | Files |
|----------|------|--------|
| Support triage | choice | `support-triage.{csv,yaml}` |
| Content moderation | noul | `content-moderation.{csv,yaml}` |
| Lead scoring | score | `lead-scoring.{csv,yaml}` |

```bash
just example-triage
just example-moderation
just example-lead-scoring
```

## Dev Requirements

- [Nim](https://nim-lang.org/) **≥ 2.2.12**
- [Atlas](https://github.com/nim-lang/atlas) (vendored deps under `deps/`)
- OpenSSL (`-d:ssl` for HTTPS)
- **`TYPESAFE_API_KEY`**
- **[just](https://github.com/casey/just)** (optional)

## Major Dependencies

- Jev access is via [jev-nim-client](https://github.com/aboisvert/jev-nim-client).
- Parallelism from [Malebolgia](https://github.com/Araq/malebolgia).
- HTTP concurrency uses [asyncdispatch](https://nim-lang.org/docs/asyncdispatch.html) through `jev-nim-client`

## Setup

```bash
atlas replay           # check out pinned deps/ from atlas.lock and write nim.cfg
```

Dependency versions are pinned in **`atlas.lock`**. After changing `jevvy.nimble` requirements, run `atlas install`, then refresh the lock with `atlas pin`. Use `atlas changed` to see drift from the lock file.

## Development

```bash
just test              # or: nimble test
just run               # CLI help
just build             # out/jevvy
```

Run an example (with `.env` or exported key):

```bash
just example-triage
```

Or:

```bash
nim r -d:ssl --threads:on --path:src src/jevvy.nim -- --input examples/support-triage.csv
```

## Release

Bump [`VERSION`](VERSION), then:

```bash
just release
```

Produces `out/jevvy-osx-arm64-v<VERSION>-bin` and/or `out/jevvy-linux-x64-v<VERSION>-bin` (see `just release` for platform rules). Linux cross-build uses `docker/linux.Dockerfile`.

## Related links

- [TypeSafe AI / Jev documentation](https://docs.typesafe.ai/)
- [jev-nim-client](https://github.com/aboisvert/jev-nim-client)
- [Malebolgia](https://github.com/Araq/malebolgia)
