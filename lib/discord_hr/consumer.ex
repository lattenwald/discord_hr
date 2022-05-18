defmodule DiscordHr.Consumer do
  use Nostrum.Consumer

  use Bitwise, only_operators: true
  # https://discord.com/developers/docs/resources/channel#message-object-message-flags
  @flag_ephemeral 1 <<< 6

  alias Nostrum.Api
  alias DiscordHr.Guilds

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:GUILD_AVAILABLE, guild = %{id: guild_id}, _ws_state}) do
    IO.puts "guild #{guild_id}"
    Guilds.new_guild guild
    icons = DiscordHr.Icons.list
    options = ["random" | icons] |> Enum.map(& %{name: String.downcase(&1), description: &1, type: 1})
    commands = [
      %{name: "icon", description: "Set icon", options: options},
      %{name: "pingon", description: "Set role for pings in this channel"},
      %{name: "pingoff", description: "Remove role for pings in this channel"},
    ]
    Api.bulk_overwrite_guild_application_commands(guild_id, commands)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 2,
    member: %{user: %{username: username}},
    data: %{name: "icon", options: [%{name: key}]}
  }, _ws_state}) do
    {key, icon} = case key do
      "random" -> DiscordHr.Icons.random
      _ -> {key, DiscordHr.Icons.icon key}
    end
    set_icon(interaction, key, icon, "#{username} used /icon #{key}")
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 2,
    guild_id: guild_id, channel_id: channel_id,
    member: %{user: %{id: user_id, username: username}, roles: user_roles},
    data: %{name: "pingon"}
  }, _ws_state}) do
    %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} = Guilds.get(guild_id)
    case roles |> Enum.find(fn ({_, %{name: name}}) -> name == channel_name end) do
      nil ->
        respond_to_interaction interaction, "There's no ping role for this channel"
      {role_id, _} ->
        if Enum.member? user_roles, role_id do
          respond_to_interaction interaction, "You already have role `@#{channel_name}`"
        else
          case Api.add_guild_member_role(guild_id, user_id, role_id, "#{username} used /pingme in #{channel_name}") do
            {:ok} ->
              respond_to_interaction interaction, "Added `@#{channel_name}` role"
            {:error, %{response: %{message: message}}} ->
              respond_to_interaction interaction, "Error: #{message}"
          end
        end
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 2,
    guild_id: guild_id, channel_id: channel_id,
    member: %{user: %{id: user_id, username: username}, roles: user_roles},
    data: %{name: "pingoff"}
  }, _ws_state}) do
    %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} = Guilds.get(guild_id)
    case roles |> Enum.find(fn ({_, %{name: name}}) -> name == channel_name end) do
      nil ->
        respond_to_interaction interaction, "There's no ping role for this channel"
      {role_id, _} ->
        if Enum.member? user_roles, role_id do
          case Api.remove_guild_member_role(guild_id, user_id, role_id, "#{username} used /pingme in #{channel_name}") do
            {:ok} ->
              respond_to_interaction interaction, "Removed `@#{channel_name}` role"
            {:error, %{response: %{message: message}}} ->
              respond_to_interaction interaction, "Error: #{message}"
          end
        else
            respond_to_interaction interaction, "You don't have role `@#{channel_name}` set"
        end
    end
  end


  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    IO.inspect interaction
  end

  def handle_event({:GUILD_ROLE_CREATE, {guild_id, role}, _ws_state}) do
    Guilds.role_created guild_id, role
  end

  def handle_event({:GUILD_ROLE_DELETE, {guild_id, role}, _ws_state}) do
    Guilds.role_deleted guild_id, role
  end

  def handle_event({:GUILD_ROLE_UPDATE, {guild_id, _old, new}, _ws_state}) do
    Guilds.role_updated guild_id, new
  end

  def handle_event({:CHANNEL_UPDATE, {_old, new}, _ws_state}) do
    Guilds.channel_updated new
  end

  def handle_event({:CHANNEL_CREATE, channel, _ws_state}) do
    Guilds.channel_updated channel
  end

  def handle_event({:CHANNEL_DELETE, channel, _ws_state}) do
    Guilds.channel_deleted channel
  end

  def handle_event({event, _, _}) do
    IO.inspect event
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  defp set_icon(interaction = %{guild_id: guild_id}, key, icon, reason \\ nil) do
    case Nostrum.Api.modify_guild(guild_id, [icon: icon], reason) do
      {:error, %{status_code: 429, response: %{retry_after: retry_after}}} ->
        respond_to_interaction interaction, "Retry in #{retry_after} seconds"
      {:error, %{response: %{message: message}}} ->
        respond_to_interaction interaction, "Error: #{message}"
      {:ok, _} ->
        respond_to_interaction interaction, "Changed server icon to `#{key}`"
    end
  end

  defp respond_to_interaction(interaction, text) do
    Api.create_interaction_response(interaction, %{type: 4, data: %{content: text, flags: @flag_ephemeral}})
  end

end
