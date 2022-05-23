defmodule DiscordHr.MixProject do
  use Mix.Project

  def project do
    [
      app: :discord_hr,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {DiscordHr.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:toml_config_provider, "~> 0.2.0"},
      {:nostrum, git: "https://github.com/Kraigie/nostrum.git"},
      {:epmdless, "~> 0.3.0"}
      # {:memento, "~> 0.3.2"}
    ]
  end

  defp releases do
    [
      docker: [
        include_executables_for: [:unix],
        config_providers: [{TomlConfigProvider, "/app/config.toml"}],
        steps: [:assemble, :tar],
        path: "/app/release"
      ],
      dev: [
        include_executables_for: [:unix],
        cookie: "discord_hr"
      ],
      prod: [
        include_executables_for: [:unix],
        config_providers: [{TomlConfigProvider, "config.toml"}],
        steps: [:assemble, :tar],
        path: "releases/"
      ]
    ]
  end
end
