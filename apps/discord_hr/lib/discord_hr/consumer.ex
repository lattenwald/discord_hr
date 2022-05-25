defmodule DiscordHr.Consumer do
  require Logger

  use Nostrum.Consumer

  use Bitwise, only_operators: true
  # https://discord.com/developers/docs/resources/channel#message-object-message-flags
  @flag_ephemeral 1 <<< 6
  @new_voice_permissions 1 <<< 4 ||| 1 <<< 10 ||| 1 <<< 20

  alias Nostrum.Api
  alias Nostrum.Cache

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:GUILD_AVAILABLE, %{id: guild_id}, _ws_state}) do
    IO.puts "guild #{guild_id}"
    icons = DiscordHr.Icons.list
    choices = ["random" | icons] |> Enum.map(& %{name: &1, value: &1})
    commands = [
      %{name: "icon",
        description: "Set icon",
        description_localizations: %{"ru" => "Установить иконку"},
        options: [%{
          name: "icon",
          name_localizations: %{"ru" => "иконка"},
          description: "choose icon",
          description_localizations: %{"ru" => "выберите иконку"},
          type: 3, choices: choices, required: true}]
      },
      %{name: "pingon",
        description_localizations: %{"ru" => "Включить роль для пингов в этом канале"},
        description: "Set role for pings in this channel"},
      %{name: "pingoff",
        description_localizations: %{"ru" => "Убрать роль для пингов в этом канале"},
        description: "Remove role for pings in this channel"},
      %{name: "setup",
        description: "Configuration",
        default_member_permission: "0",
        options: [%{
          name: "voice",
          description: "Voice channel to manage",
          type: 7
        }]
      }
    ]
    set_guild_commands(guild_id, commands)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 2,
    member: %{user: %{username: username}},
    data: %{name: "icon", options: [%{name: "icon", value: key}]}
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
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
      case roles |> Enum.find(fn ({_, %{name: name}}) -> name == channel_name end) do
        nil ->
          respond_to_interaction interaction, "There's no ping role for this channel"
        {role_id, _} ->
          if Enum.member? user_roles, role_id do
            respond_to_interaction interaction, "You already have role `@#{channel_name}`"
          else
            case Api.add_guild_member_role(guild_id, user_id, role_id, "#{username} used /pingme in #{channel_name}") |> IO.inspect do
              {:ok} ->
                respond_to_interaction interaction, "Added `@#{channel_name}` role"
              {:error, %{response: %{message: message}}} ->
                respond_to_interaction interaction, "Error: #{message}"
            end
          end
      end
    else
      _ -> respond_to_interaction interaction, "Cannot find channel"
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 2,
    guild_id: guild_id, channel_id: channel_id,
    member: %{user: %{id: user_id, username: username}, roles: user_roles},
    data: %{name: "pingoff"}
  }, _ws_state}) do
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
      case roles |> Enum.find(fn ({_, %{name: name}}) -> name == channel_name end) do
        nil ->
          respond_to_interaction interaction, "There's no ping role for this channel"
        {role_id, _} ->
          if Enum.member? user_roles, role_id do
            case Api.remove_guild_member_role(guild_id, user_id, role_id, "#{username} used /pingme in #{channel_name}") |> IO.inspect do
              {:ok} ->
                respond_to_interaction interaction, "Removed `@#{channel_name}` role"
              {:error, %{response: %{message: message}}} ->
                respond_to_interaction interaction, "Error: #{message}"
            end
          else
              respond_to_interaction interaction, "You don't have role `@#{channel_name}` set"
          end
      end
    else
      _ -> respond_to_interaction interaction, "Cannot find channel"
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 2,
    guild_id: guild_id,
    data: %{name: "setup", options: [%{name: "voice", value: channel_id, type: 7}]}
  }, _ws_state}) do
    with %{channels: %{^channel_id => %{name: channel_name, type: 2}}} <- Cache.GuildCache.get!(guild_id) do
      {:ok, _} = Storage.write %Storage.Voice{guild_id: guild_id, channel_id: channel_id}
      respond_to_interaction interaction, "Channel 🔊#{channel_name} is set as default voice channel"
    else
      _ ->
        Logger.warning "Can't setup default voice channel #{channel_id} for #{guild_id}"
        respond_to_interaction interaction, "Can't setup this channel as default voice channel"
    end
  end


  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    IO.inspect interaction
  end

  def handle_event({:CHANNEL_UPDATE, {%{name: old_name, guild_id: guild_id}, %{name: new_name}}, _ws_state}) do
    if old_name != new_name do
      %{roles: roles} = Cache.GuildCache.get! guild_id
      case roles |> Enum.find(fn ({_, %{name: name}}) -> name == old_name end) do
        nil -> :ok
        {role_id, _} ->
          Api.modify_guild_role guild_id, role_id, [name: new_name], "channel #{old_name} was renamed to #{new_name}"
      end
    end
  end

  def handle_event({:CHANNEL_DELETE, %{guild_id: guild_id, id: channel_id}, _ws_state}) do
    case Storage.Voice.get(guild_id) do
      {:ok, %{guild_id: ^guild_id, channel_id: ^channel_id}} ->
        :ok = Storage.delete Storage.Voice, guild_id
      _ ->
        :ok
    end
  end

  def handle_event({:VOICE_STATE_UPDATE, %{guild_id: guild_id, channel_id: channel_id, member: %{user: %{id: userid, username: username}}}, _ws_state}) do
    with {:ok, %{guild_id: ^guild_id, channel_id: default_voice}} <- Storage.Voice.get(guild_id),
         {:ok, %{parent_id: parent_id}} <- Nostrum.Cache.ChannelCache.get(default_voice),
         {:ok, %{channels: channels, voice_states: voice_states}} <- Nostrum.Cache.GuildCache.get(guild_id),
         voice_channels_of_interest <- channels |> Enum.filter(fn {id, %{type: 2, parent_id: ^parent_id}} -> id != default_voice; (_) -> false end) |> Enum.map(fn {id, _} -> id end) |> MapSet.new,
         populated_voice_channels <- voice_states |> Enum.map(fn %{channel_id: channel_id} -> channel_id end) |> MapSet.new
    do
      to_remove = MapSet.difference voice_channels_of_interest, populated_voice_channels
      Logger.info "removing #{MapSet.size to_remove} empty voice channel(s)"
      to_remove |> Enum.each(&Api.delete_channel(&1, "removing empty managed voice channel"))

      if channel_id == default_voice do
        {:ok, %{id: new_channel_id}} = Api.create_guild_channel(guild_id, %{name: "#{username}'s Channel", type: 2, parent_id: parent_id, nsfw: false})
        {:ok} = Api.edit_channel_permissions(new_channel_id, userid, %{type: :member, allow: @new_voice_permissions})
        {:ok, _} = Api.modify_guild_member(guild_id, userid, channel_id: new_channel_id)
      end
    else
      _ -> :ok
    end
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

  def set_guild_commands(guild_id, commands) do
    case Api.bulk_overwrite_guild_application_commands(guild_id, commands) do
      {:error, %{status_code: 429, response: %{retry_after: retry_after}}} ->
        Logger.warning "failed setting guild application commands for guild #{guild_id}, will retry in #{retry_after} seconds"
        :timer.apply_after(floor(retry_after * 1000) + 100, __MODULE__, :set_guild_commands, [guild_id, commands])
      {:error, %{response: %{message: message}}} ->
        retry_after = 10
        Logger.warning "failed setting guild application commands for guild #{guild_id}: #{message} will retry in #{retry_after} seconds"
        :timer.apply_after(floor(retry_after * 1000) + 100, __MODULE__, :set_guild_commands, [guild_id, commands])
      {:ok, _} ->
        :ok
    end
  end

end
