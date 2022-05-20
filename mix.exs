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
      extra_applications: [:logger],
      mod: {DiscordHr.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:toml_config_provider, "~> 0.2.0"},
      {:nostrum, git: "https://github.com/Kraigie/nostrum.git"}
      # {:nostrum, "~> 0.5.1"}
    ]
  end

  defp releases do
    [
      prod: [
        include_executables_for: [:unix],
        config_providers: [
          {TomlConfigProvider, "/app/config.toml"}
        ],
        steps: [:assemble, :tar],
        path: "/app/release"
      ]
    ]
  end
end
