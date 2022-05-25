defmodule Storage.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    nodes = [node()]
    Memento.stop
    Memento.Schema.create(nodes)
    Memento.start

    Memento.Table.create(Storage.Voice, disc_copies: nodes)
    children = [
      # Starts a worker by calling: Storage.Worker.start_link(arg)
      # {Storage.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Storage.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
