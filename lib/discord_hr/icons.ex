defmodule DiscordHr.Icons do
  require Logger
  use Agent
  use DiscordHr.CommandModule

  def start_link(_) do
    {:ok, files} = File.ls("icons")
    files = files |> Enum.filter(&(Path.extname(&1) == ".jpg"))

    data =
      files
      |> Enum.map(fn file ->
        icon = "data:image/jpeg;base64," <> Base.encode64(File.read!("icons/#{file}"))
        {String.downcase(Path.rootname(file)), icon}
      end)
      |> Enum.into(%{})

    Agent.start_link(fn -> data end, name: __MODULE__)
  end

  def list do
    Agent.get(__MODULE__, &Map.keys(&1))
  end

  def icon(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  def random do
    Agent.get(__MODULE__, &Enum.random(&1))
  end

  @impl true
  def guild_application_command(_) do
    icons = DiscordHr.Icons.list()
    choices = ["random" | icons] |> Enum.map(&%{name: &1, value: &1})

    %{
      name: "icon",
      description: "Set icon",
      description_localizations: %{"ru" => "Установить иконку"},
      options: [
        %{
          name: "icon",
          name_localizations: %{"ru" => "иконка"},
          description: "choose icon",
          description_localizations: %{"ru" => "выберите иконку"},
          type: 3,
          choices: choices,
          required: true
        }
      ]
    }
  end

  @impl true
  def command_handlers, do: {"icon", :set_icon}

  def handle_application_command(
        :set_icon,
        interaction = %{member: %{user: %{username: username}}},
        [%{"icon" => key}]
      ) do
    {key, icon} =
      case key do
        "random" -> DiscordHr.Icons.random()
        _ -> {key, DiscordHr.Icons.icon(key)}
      end

    set_icon(interaction, key, icon, "#{username} used /icon #{key}")
  end

  defp set_icon(interaction = %{guild_id: guild_id}, key, icon, reason) do
    case Nostrum.Api.modify_guild(guild_id, [icon: icon], reason) do
      {:error, %{status_code: 429, response: %{retry_after: retry_after}}} ->
        DiscordHr.respond_to_interaction(interaction, "Retry in #{retry_after} seconds")

      {:error, %{response: %{message: message}}} ->
        DiscordHr.respond_to_interaction(interaction, "Error: #{message}")

      {:ok, _} ->
        DiscordHr.respond_to_interaction(interaction, "Changed server icon to `#{key}`")
    end
  end

  @impl true
  def interaction_react(interaction, path) do
    {_, handlers} = command_handlers()
    interaction_react(interaction, path, handlers)
  end

  def interaction_react(interaction, data, reaction) when is_atom(reaction) do
    handle_application_command(reaction, interaction, data)
  end

  def interaction_react(interaction, path = [name | rest], handlers) do
    case Map.get(handlers, name, nil) do
      nil ->
        Logger.warning(
          "no handler for interaction #{inspect(path)} #{inspect(handlers)}~n#{inspect(interaction)}"
        )

        DiscordHr.respond_to_interaction(
          interaction,
          "Can't handle that in `#{__MODULE__}`, report to bot author"
        )

      reaction when is_atom(reaction) ->
        handle_application_command(reaction, interaction, rest)

      more_handlers ->
        interaction_react(interaction, rest, more_handlers)
    end
  end
end
