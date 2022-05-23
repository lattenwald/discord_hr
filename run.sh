#!/bin/sh
exec docker run \
    -v `pwd`/config-dev.toml:/app/config.toml \
    -v `pwd`/storage.bin:/app/storage.bin \
    -v `pwd`/icons:/app/icons \
    -v `pwd`/erl_crash.dump:/app/erl_crash.dump \
    -i -t discord_hr $@
