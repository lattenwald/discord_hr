FROM elixir:alpine AS builder

RUN apk add git

ADD . /app
WORKDIR /app
RUN rm config/*
RUN rm -rf _build deps
RUN rm -f storage.bin

ENV MIX_ENV prod
RUN mix do local.hex --force, local.rebar --force
RUN mix deps.get
RUN mix do deps.compile, compile, release


FROM elixir:alpine

RUN mkdir /app
WORKDIR /app
COPY --from=builder /app/release/prod-*.tar.gz /app/
RUN tar xzf prod-*.tar.gz

VOLUME ["/app/config.toml", "/app/icons",  "/app/storage.bin", "/app/erl_crash.dump"]

ENTRYPOINT ["/app/bin/prod"]
CMD ["start"]
