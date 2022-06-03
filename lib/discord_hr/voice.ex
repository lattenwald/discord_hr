defmodule DiscordHr.Voice do
  require Logger
  use DiscordHr.CommandModule

  use Bitwise, only_operators: true
  @new_voice_permissions 1 <<< 4 ||| 1 <<< 10 ||| 1 <<< 20

  alias Nostrum.Api
  alias Nostrum.Struct.Component
  alias DiscordHr.Storage
  alias Nostrum.Cache

  @command_handlers {"voice", %{
    "channel" => :set_voice_channel,
    "names" => %{
      "list" => :get_voice_names,
      "add" => :add_voice_name,
      "delete" => :delete_voice_name,
      "rename" => :toggle_voice_renaming
    }
  } }
  @impl true
  def command_handlers, do: @command_handlers

  @component_handlers {"voice", %{
    "delete" => %{
      "select" => :delete_select,
      "button" => :delete_button
    }
  }}
  @impl true
  def component_handlers, do: @component_handlers

  @command %{
    name: "voice",
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

  @impl true
  def guild_application_command(_), do: @command

  @impl true
  def interaction_react(interaction, path) do
    {_, handlers} = command_handlers()
    interaction_react(interaction, path, handlers)
  end
  def interaction_react(interaction, path = [name | rest], handlers) do
    case Map.get(handlers, name, nil) do
      nil ->
        Logger.warning "no handler for interaction #{inspect path} #{inspect handlers}~n#{inspect interaction}"
        DiscordHr.respond_to_interaction interaction, "Can't handle that in `#{__MODULE__}`, report to bot author"
      reaction when is_atom(reaction) ->
        handle_application_command(reaction, interaction, rest)
      more_handlers ->
        interaction_react(interaction, rest, more_handlers)
    end
  end

  @impl true
  def component_react(interaction, path) do
    {_, handlers} = component_handlers()
    component_react(interaction, path, handlers)
  end
  def component_react(interaction, path = [name | rest], handlers) do
    case Map.get(handlers, name, nil) do
      nil ->
        Logger.warning "no handler for interaction #{inspect path} #{inspect handlers}~n#{inspect interaction}"
        DiscordHr.respond_to_component interaction, "Can't handle that in `#{__MODULE__}`, report to bot author"
      reaction when is_atom(reaction) ->
        handle_component(reaction, interaction, rest)
      more_handlers ->
        component_react(interaction, rest, more_handlers)
    end
  end

  def handle_component(:delete_select, interaction = %{guild_id: guild_id, data: %{values: selected}}, []) do
    components = delete_channel_components(guild_id, selected)
    DiscordHr.respond_to_component interaction, "", components
  end

  def handle_component(:delete_button,
    interaction = %{
      guild_id: guild_id,
      message: %{
        components: [%{
          components: [%{
            custom_id: "voice:delete:select",
            options: options
          }]
        } | _]
      }
    }, [])
  do
    with remove <- options |> Enum.filter(& Map.get(&1, :default, false)) |> Enum.map(& &1.value) do
      names = Storage.get([guild_id, :voice_names], [])
      new_names = names |> Enum.filter(& not Enum.member?(remove, &1))
      Storage.put([guild_id, :voice_names], new_names)
      DiscordHr.respond_to_component interaction, "Removed **#{length(names) - length(new_names)}** voice names"
    else
      _ ->
        DiscordHr.respond_to_component interaction, "nothing to delete"
    end
  end


  def handle_application_command(:get_voice_names, interaction = %{guild_id: guild_id}, _) do
    on = Storage.get([guild_id, :voice_renaming_on], false)
    on_text = "Automatic voice renaming is **#{if on, do: "on", else: "off"}**"
    case Storage.get([guild_id, :voice_names], []) do
      [] -> DiscordHr.respond_to_interaction interaction, "#{on_text}\nNo names configured"
      names ->
        text = names |> Enum.zip(1 .. length(names)) |> Enum.map(fn {name, num} -> "#{num}. `#{name}`" end) |> Enum.join("\n")
        DiscordHr.respond_to_interaction(interaction, "#{on_text}\nConfigured voice names:\n#{text}")
    end
  end

  def handle_application_command(:set_voice_channel, interaction = %{guild_id: guild_id}, [%{"id" => channel_id}]) do
    with %{channels: %{^channel_id => %{name: channel_name, type: 2}}} <- Cache.GuildCache.get!(guild_id) do
      Storage.put([guild_id, :default_voice], channel_id)
      DiscordHr.respond_to_interaction interaction, "Channel 🔊#{channel_name} is set as default voice channel"
    else
      _ ->
        Logger.warning "Can't setup default voice channel #{channel_id} for #{guild_id}"
        DiscordHr.respond_to_interaction interaction, "Can't setup this channel as default voice channel"
    end
  end

  def handle_application_command(:add_voice_name, interaction = %{guild_id: guild_id}, [%{"name" => name}]) do
    names = Storage.get([guild_id, :voice_names], [])
    if Enum.member?(names, name) do
      DiscordHr.respond_to_interaction interaction, "Voice name already present"
    else
      names = [name | names]
      Storage.put([guild_id, :voice_names], names)
      DiscordHr.respond_to_interaction interaction, "Voice name saved"
    end
  end

  def handle_application_command(:delete_voice_name, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, :voice_names], []) do
      [] ->
        DiscordHr.respond_to_interaction interaction, "There are 0 voice names, nothing to delete"
      _ ->
        components = delete_channel_components(guild_id)
        DiscordHr.respond_to_interaction interaction, "Remove voice name", components
    end
  end

  def handle_application_command(:toggle_voice_renaming, interaction = %{guild_id: guild_id}, [%{"on" => on}]) do
    Storage.put([guild_id, :voice_renaming_on], on)
    DiscordHr.respond_to_interaction interaction, "Automatic voice renaming is turned **#{if on, do: "on", else: "off"}**"
  end

  @impl true
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

  def handle_event(_), do: :noop

  defp delete_channel_components(guild_id, selected \\ []) do
    names = Storage.get([guild_id, :voice_names], nil)
    options = names |> Enum.map(&(%Component.Option{label: "#{&1}", value: "#{&1}", default: Enum.member?(selected, &1)}))
    menu = Component.SelectMenu.select_menu("voice:delete:select",
      placeholder: "Select names to delete",
      min_values: 0,
      max_values: min(length(options), 20),
      options: options)
    row1 = Component.ActionRow.action_row()
    row1 = Component.ActionRow.put row1, menu
    [
      row1,
      Component.ActionRow.action_row([
        Component.Button.interaction_button("DELETE", "voice:delete:button", style: 4, disabled: selected == []),
        Component.Button.interaction_button("Cancel", "cancel", style: 1),
      ])
    ]
  end



end
