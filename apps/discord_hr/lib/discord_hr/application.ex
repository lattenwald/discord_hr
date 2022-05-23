defmodule DiscordHr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @storage "storage.bin"

  @impl true
  def start(_type, _args) do
    children = [
      {DiscordHr.Storage, @storage},
      DiscordHr.Icons,
      DiscordHr.Consumer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: DiscordHr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
