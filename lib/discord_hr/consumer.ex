defmodule DiscordHr.Consumer do
  require Logger

  use Nostrum.Consumer

  use Bitwise, only_operators: true
  # https://discord.com/developers/docs/resources/channel#message-object-message-flags
  @flag_ephemeral 1 <<< 6
  @new_voice_permissions 1 <<< 4 ||| 1 <<< 10 ||| 1 <<< 20

  # application commands handlers
  @handlers %{
    "icon" => :set_icon,
    "voice" => %{
      "channel" => :set_voice_channel,
      "names" => %{
        "list" => :get_voice_names,
        "add" => :add_voice_name,
        "delete" => :delete_voice_name,
        "rename" => :toggle_voice_renaming
      }
    },
    "pingon" => :set_pingon,
    "pingoff" => :set_pingoff
  }

  alias Nostrum.Api
  alias Nostrum.Cache
  alias Nostrum.Struct.Component
  alias DiscordHr.Storage

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  ###############################################################
  # handle events
  ###############################################################

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
      %{name: "voice",
        description: "Voice configuration",
        default_member_permission: "0",
        options: [%{
          name: "channel",
          description: "choose channel to manage",
          type: 1,
          options: [%{
            name: "id",
            required: true,
            description: "Voice channel to manage",
            type: 7 }]
        }, %{
          name: "names",
          description: "voice channel names",
          type: 2,
          options: [
            %{ name: "add",
              description: "add voice channel name",
              type: 1,
              options: [%{
                name: "name",
                description: "name",
                type: 3,
                required: true
              }]
            }, %{
              name: "list",
              description: "list channel names",
              type: 1
            }, %{
              name: "delete",
              description: "delete voice name",
              type: 1
            }, %{
              name: "rename",
              description: "toggle channels renaming",
              type: 1,
              options: [%{
                name: "on",
                description: "on",
                required: true,
                type: 5
              }]
            }
            ]
          }]
        }
      ]
    set_guild_commands(guild_id, commands)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{type: 2}, _ws_state}) do
    path = extract_interaction_path(interaction)
    interaction_react(interaction, path)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 3,
    guild_id: guild_id,
    data: %{custom_id: "delete-name", values: [selected]}
  }, _ws_state}) do
    components = delete_channel_components(guild_id, selected)
    Api.create_interaction_response(interaction, %{type: 7, data: %{components: components}})
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 3,
    guild_id: guild_id,
    data: %{custom_id: "delete"},
    message: %{components: [
      %{components: [
        %{custom_id: "delete-name",
          options: options}
      ]} | _
    ]}
  }, _ws_state}) do
    with %{value: name} <- options |> Enum.find(& Map.get(&1, :default, false)) do
      names = Storage.get([guild_id, :voice_names], [])
      new_names = names |> Enum.filter(& &1 != name)
      if length(names) == length(new_names) do
        Api.create_interaction_response(interaction, %{type: 7, data: %{content: "Don't have channel name `#{name}`", components: []}})
      else
        Storage.put([guild_id, :voice_names], new_names)
        Api.create_interaction_response(interaction, %{type: 7, data: %{content: "Voice name `#{name}` deleted", components: []}})
      end
    else
      _ ->
        Api.create_interaction_response(interaction, %{type: 7, data: %{content: "nothing to delete", components: []}})
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{
    type: 3,
    data: %{custom_id: "cancel"}
  }, _ws_state}) do
    Api.create_interaction_response(interaction, %{type: 7, data: %{content: "Canceled", components: []}})
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
    case Storage.get [guild_id, :default_voice] do
      ^channel_id ->
        Storage.put [guild_id, :default_voice], nil
      _ ->
        :ok
    end
  end

  def handle_event({:VOICE_STATE_UPDATE, %{guild_id: guild_id, channel_id: channel_id, member: %{user: %{id: userid, username: username}}}, _ws_state}) do
    with default_voice when default_voice != nil <- Storage.get([guild_id, :default_voice]),
         {:ok, %{parent_id: parent_id}} <- Nostrum.Cache.ChannelCache.get(default_voice),
         {:ok, %{channels: channels, voice_states: voice_states}} <- Nostrum.Cache.GuildCache.get(guild_id),
         voice_channels_of_interest <- channels |> Enum.filter(fn {id, %{type: 2, parent_id: ^parent_id}} -> id != default_voice; (_) -> false end) |> Enum.map(fn {id, _} -> id end) |> MapSet.new,
         populated_voice_channels <- voice_states |> Enum.map(fn %{channel_id: channel_id} -> channel_id end) |> MapSet.new
    do
      to_remove = MapSet.difference voice_channels_of_interest, populated_voice_channels
      Logger.info "removing #{MapSet.size to_remove} empty voice channel(s)"
      to_remove |> Enum.each(&Api.delete_channel(&1, "removing empty managed voice channel"))

      if channel_id == default_voice do
        channel_name = if Storage.get([guild_id, :voice_renaming_on], false) do
          names = Storage.get([guild_id, :voice_names], []) |> Enum.into(MapSet.new)
          existing_channel_names = Nostrum.Cache.GuildCache.get!(guild_id).channels |> Enum.map(fn {_, %{name: n}} -> n end) |> Enum.into(MapSet.new)
          choosing_from = MapSet.difference names, existing_channel_names
          case MapSet.size(choosing_from) do
            0 -> "#{username}'s Channel"
            _ -> choosing_from |> Enum.random
          end
        else
            "#{username}'s Channel"
        end
        {:ok, %{id: new_channel_id}} = Api.create_guild_channel(guild_id, %{name: channel_name, type: 2, parent_id: parent_id, nsfw: false})
        {:ok} = Api.edit_channel_permissions(new_channel_id, userid, %{type: "member", allow: @new_voice_permissions})
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

  ###############################################################
  # application commands
  ###############################################################

  def interaction_react(interaction, path), do: interaction_react(interaction, path, @handlers)
  def interaction_react(interaction, path = [name | rest], handlers) do
    case Map.get(handlers, name, nil) do
      nil ->
        Logger.warning "no handler for interaction #{inspect path} #{inspect handlers}~n#{inspect interaction}"
        respond_to_interaction interaction, "Can't handle that, report to bot author"
      reaction when is_atom(reaction) ->
        handle_application_command(reaction, interaction, rest)
      more_handlers ->
        interaction_react(interaction, rest, more_handlers)
    end
  end

  def extract_interaction_path(nil), do: []
  def extract_interaction_path([]), do: []
  def extract_interaction_path([option]), do: extract_interaction_path(option)
  def extract_interaction_path(%{name: name, options: nil, value: value}), do: [%{name => value}]
  def extract_interaction_path(%{name: name, options: opts}) do
    [name | extract_interaction_path(opts)]
  end
  def extract_interaction_path(%{data: data}), do: extract_interaction_path(data)

  def handle_application_command(:set_icon, interaction = %{member: %{user: %{username: username}}}, [%{"icon" => key}]) do
    {key, icon} = case key do
      "random" -> DiscordHr.Icons.random
      _ -> {key, DiscordHr.Icons.icon key}
    end
    set_icon(interaction, key, icon, "#{username} used /icon #{key}")
  end

  def handle_application_command(:set_pingon, interaction = %{
    guild_id: guild_id, channel_id: channel_id,
    member: %{user: %{id: user_id, username: username}, roles: user_roles},
    data: %{name: "pingon"}
  }, _) do
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
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
    else
      _ -> respond_to_interaction interaction, "Cannot find channel"
    end
  end

  def handle_application_command(:set_pingoff, interaction = %{
    guild_id: guild_id, channel_id: channel_id,
    member: %{user: %{id: user_id, username: username}, roles: user_roles},
    data: %{name: "pingoff"}
  }, _) do
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
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
    else
      _ -> respond_to_interaction interaction, "Cannot find channel"
    end
  end

  def handle_application_command(:set_voice_channel, interaction = %{guild_id: guild_id}, [%{"id" => channel_id}]) do
    with %{channels: %{^channel_id => %{name: channel_name, type: 2}}} <- Cache.GuildCache.get!(guild_id) do
      Storage.put([guild_id, :default_voice], channel_id)
      respond_to_interaction interaction, "Channel 🔊#{channel_name} is set as default voice channel"
    else
      _ ->
        Logger.warning "Can't setup default voice channel #{channel_id} for #{guild_id}"
        respond_to_interaction interaction, "Can't setup this channel as default voice channel"
    end
  end

  def handle_application_command(:get_voice_names, interaction = %{guild_id: guild_id}, _) do
    on = Storage.get([guild_id, :voice_renaming_on], false)
    on_text = "Automatic voice renaming is **#{if on, do: "on", else: "off"}**"
    case Storage.get([guild_id, :voice_names], []) do
      [] -> respond_to_interaction interaction, "#{on_text}\nNo names configured"
      names ->
        text = names |> Enum.zip(1 .. length(names)) |> Enum.map(fn {name, num} -> "#{num}. `#{name}`" end) |> Enum.join("\n")
        respond_to_interaction(interaction, "#{on_text}\nConfigured voice names:\n#{text}")
    end
  end

  def handle_application_command(:add_voice_name, interaction = %{guild_id: guild_id}, [%{"name" => name}]) do
    names = Storage.get([guild_id, :voice_names], [])
    if Enum.member?(names, name) do
      respond_to_interaction interaction, "Voice name already present"
    else
      names = [name | names]
      Storage.put([guild_id, :voice_names], names)
      respond_to_interaction interaction, "Voice name saved"
    end
  end

  def handle_application_command(:delete_voice_name, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, :voice_names], []) do
      [] ->
        respond_to_interaction interaction, "There are 0 voice names, nothing to delete"
      _ ->
        components = delete_channel_components(guild_id)
        Api.create_interaction_response(interaction, %{type: 4, data: %{content: "Remove voice name", components: components, flags: @flag_ephemeral}})
    end
  end

  defp delete_channel_components(guild_id, selected \\ nil) do
    names = Storage.get([guild_id, :voice_names], nil)
    options = names |> Enum.map(&(%Component.Option{label: "#{&1}", value: "#{&1}", default: &1 == selected}))
    menu = Component.SelectMenu.select_menu("delete-name", options: options)
    row1 = Component.ActionRow.action_row()
    row1 = Component.ActionRow.put row1, menu
    [
      row1,
      Component.ActionRow.action_row([
        Component.Button.interaction_button("DELETE", "delete", style: 4, disabled: selected == nil),
        Component.Button.interaction_button("Cancel", "cancel", style: 1),
      ])
    ]
  end

  def handle_application_command(:toggle_voice_renaming, interaction = %{guild_id: guild_id}, [%{"on" => on}]) do
    Storage.put([guild_id, :voice_renaming_on], on)
    respond_to_interaction interaction, "Automatic voice renaming is turned **#{if on, do: "on", else: "off"}**"
  end

  ###############################################################
  # helpers
  ###############################################################

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
