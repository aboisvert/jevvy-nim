# jevvy CSV CLI — run with `just example-triage` (requires TYPESAFE_API_KEY in .env)

set shell := ["sh", "-uc"]
set dotenv-load := true
set dotenv-required := true

default:
    @just --list

nim_flags := "-d:ssl --threads:on --path:src"

# Show CLI usage
run:
    nim r {{nim_flags}} src/jevvy.nim -- --help 2>&1 || nim r {{nim_flags}} src/jevvy.nim

_run *ARGS:
    nim r {{nim_flags}} src/jevvy.nim -- {{ARGS}}

# Support triage (choice) example
example-triage:
    just _run --config examples/support-triage.yaml --input examples/support-triage.csv --output /tmp/jevvy-support-triage-out.csv

# Content moderation (noul) example
example-moderation:
    just _run --config examples/content-moderation.yaml --input examples/content-moderation.csv --output /tmp/jevvy-content-moderation-out.csv

# Lead scoring (score) example
example-lead-scoring:
    just _run --config examples/lead-scoring.yaml --input examples/lead-scoring.csv --output /tmp/jevvy-lead-scoring-out.csv

test:
    nimble test

build:
    nim c -d:release {{nim_flags}} -o:out/jevvy src/jevvy.nim

# Build versioned release binaries (see VERSION). macOS arm64: host; Linux x86_64: Docker.
release:
    #!/usr/bin/env sh
    set -eu
    VERSION="$(tr -d ' \n\r' < VERSION)"
    if [ -z "$VERSION" ]; then
      echo "VERSION file is empty or missing" >&2
      exit 1
    fi
    smoke_test() {
      if ! "$1" 2>&1 | grep -q 'Usage: jevvy'; then
        echo "Smoke test failed for $1" >&2
        exit 1
      fi
    }
    mkdir -p out
    case "$(uname -s)-$(uname -m)" in
      Darwin-arm64)
        osx_out="out/jevvy-osx-arm64-v${VERSION}-bin"
        nim c -d:release -d:ssl --threads:on --path:src -o:"$osx_out" src/jevvy.nim
        smoke_test "$osx_out"
        linux_out="out/jevvy-linux-x64-v${VERSION}-bin"
        just docker-linux-build
        cid="$(docker create jevvy-linux-build)"
        docker cp "$cid:/jevvy" "$linux_out"
        docker rm "$cid" >/dev/null
        chmod +x "$linux_out"
        docker run --rm --platform linux/amd64 jevvy-linux-build /jevvy 2>&1 | grep -q 'Usage: jevvy'
        echo "Wrote $osx_out and $linux_out"
        ;;
      Linux-x86_64|Linux-amd64)
        linux_out="out/jevvy-linux-x64-v${VERSION}-bin"
        nim c -d:release -d:ssl --threads:on --path:src -o:"$linux_out" src/jevvy.nim
        smoke_test "$linux_out"
        echo "Wrote $linux_out"
        ;;
      *)
        echo "Unsupported platform for release: $(uname -s) $(uname -m)" >&2
        exit 1
        ;;
    esac

# Build Linux binary in Docker
docker-linux-build:
    DOCKER_BUILDKIT=1 docker build --platform linux/amd64 -f docker/linux.Dockerfile -t jevvy-linux-build .


_list-nim-executables $ROOT:
  #!/usr/bin/env sh
  set -eu
  ROOT=${ROOT:-$(pwd)}
  find "$ROOT" -type f -name '*.nim' -exec sh -c '
    set +e
    for f do
      # check if .nim file has executable sibling (no extension)
      base=$(basename "$f" .nim)
      basepath=$(dirname "$f")
      if [ -f "$basepath/$base" ]; then
        printf "%s\n" "$basepath/$base"
      fi
    done
  ' sh {} +

list-executables:
  #!/usr/bin/env sh
  set -eu
  ROOT=$(pwd)
  just _list-nim-executables $ROOT/src/
  just _list-nim-executables $ROOT/test/
  if [ -d "$ROOT/out" ]; then
    find "$ROOT/out" -type f
  fi

rm-executables:
  #!/usr/bin/env sh
  just list-executables | xargs -I {} rm -f {}
