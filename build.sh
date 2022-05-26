#!/bin/sh
docker pull elixir:alpine
docker build --network host -t discord_hr .
