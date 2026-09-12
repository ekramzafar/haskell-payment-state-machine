FROM haskell:9.10-bookworm

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libpq-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY PaySwitch.cabal ./

RUN cabal update \
    && cabal build --only-dependencies -j2

COPY app ./app
COPY src ./src
COPY test ./test

RUN cabal build -j2

EXPOSE 8080

CMD ["cabal", "run", "PaySwitch"]