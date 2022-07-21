#!/bin/sh
exec docker run \
    -v `pwd`/config.toml:/app/config.toml \
    -v `pwd`/storage.bin:/app/storage.bin \
    -v `pwd`/icons:/app/icons \
    -i -t discord_hr $@
