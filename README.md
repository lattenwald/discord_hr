# DiscordHr

Discord bot managing voice channels, roles and stuff.

## Installation

Checkout

Build docker image with `./build.sh`

Move it to server via docker hub or somehow

Copy `config.toml.example` to `config.toml`, put your discord bot token there. Discord token is obtainable from https://discord.com/developers/applications, create an app there, a bot in this app. Bot requires permissions to manage guild, channels, roles and to move members.

Copy empty storage `storage.bin.empty` from repo into `storage.bin` to be mounted into docker: `cp storage.bin.empty storage.bin` in case you're going to use `run.sh`

Run the container: `./run.sh`

## Systemd

My systemd service, modify and use at will.

```
[Unit]
Description=HR discord bot
Requires=docker.service
After=docker.service

[Install]
WantedBy=multi-user.target

[Service]
User=user
Restart=always
RestartSec=30
ExecStart=/usr/bin/docker run --name=discord_hr --rm -v /home/user/discord_hr/config.toml:/app/config.toml -v /home/user/discord_hr/storage.bin:/app/storage.bin -v /home/user/discord_hr/icons:/app/icons lattenwald/discord_hr:latest
ExecStop=/usr/bin/docker stop -t 2 lattenwald/discord_hr:latest
ExecStopPost=/usr/bin/docker rm -f lattenwald/discord_hr:latest
```
