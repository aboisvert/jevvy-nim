FROM nimlang/nim:2.2.12

WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*

COPY . /build/jevvy
WORKDIR /build/jevvy

RUN curl -fsSL https://raw.githubusercontent.com/nim-lang/atlas/HEAD/install.sh | bash -
ENV PATH="/root/.nimble/bin:${PATH}"

# BuildKit may reuse cached layers; drop any partial deps/ checkouts from the context.
RUN find deps -mindepth 1 -maxdepth 1 ! -name atlas.config -exec rm -rf {} +
RUN atlas replay
RUN nim c -d:release -d:ssl --threads:on --path:src -o:/jevvy src/jevvy.nim
