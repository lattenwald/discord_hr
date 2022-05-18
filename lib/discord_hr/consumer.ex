defmodule DiscordHr.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:GUILD_AVAILABLE, %{id: guild_id}, _ws_state}) do
    IO.puts "guild #{guild_id}"
    icons = DiscordHr.Icons.list
    options = icons |> Enum.map(& %{name: String.downcase(&1), description: &1, type: 1})
    commands = [
      %{name: "random_icon", description: "Set random icon"},
      %{name: "icon", description: "Set icon", options: options
      }
    ]
    Api.bulk_overwrite_guild_application_commands(guild_id, commands)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{type: 2, data: %{name: "random_icon"}}, _ws_state}) do
    {key, icon} = DiscordHr.Icons.random
    set_icon(interaction, key, icon)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{type: 2, data: %{name: "icon", options: [%{name: key}]}}, _ws_state}) do
    icon = DiscordHr.Icons.icon key
    set_icon(interaction, key, icon)
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    IO.inspect interaction
  end

  def handle_event({event, _, _}) do
    IO.inspect event
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  defp set_icon(interaction = %{guild_id: guild_id}, key, icon) do
    case Nostrum.Api.modify_guild(guild_id, icon: icon) do
      {:error, %{status_code: 429, response: %{retry_after: retry_after}}} ->
        Api.create_interaction_response(interaction, %{type: 4, data: %{content: "Retry in #{retry_after} seconds"}})
      {:error, %{response: %{message: message}}} ->
        Api.create_interaction_response(interaction, %{type: 4, data: %{content: "Error: #{message}"}})
      {:ok, _} ->
        Api.create_interaction_response(interaction, %{type: 4, data: %{content: "Changed server icon to `#{key}`"}})
    end
  end

end
