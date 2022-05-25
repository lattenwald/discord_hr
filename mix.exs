defmodule DiscordManager.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:epmdless, "~> 0.3.0"}
    ]
  end

  defp releases do
    [
      dev: [
        include_executables_for: [:unix],
        applications: [discord_hr: :permanent, storage: :permanent, epmdless: :permanent],
        cookie: "discord_hr"
      ],
      prod: [
        include_executables_for: [:unix],
        applications: [discord_hr: :permanent],
        config_providers: [{TomlConfigProvider, "config.toml"}],
        steps: [:assemble, :tar],
        path: "releases/"
      ]
    ]
  end

end
