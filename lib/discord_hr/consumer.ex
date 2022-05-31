defmodule DiscordHr.Consumer do
  require Logger

  use Nostrum.Consumer

  alias Nostrum.Api
  alias Nostrum.Cache

  @command_modules [DiscordHr.Voice, DiscordHr.Icons]

  # application commands handlers
  @command_handlers %{
    "pingon" => :set_pingon,
    "pingoff" => :set_pingoff
  }

  defp command_handlers do
    @command_modules |> List.foldl(@command_handlers, fn module, acc ->
      case  module.command_handlers() do
        {key, _} -> Map.put_new(acc, key, {:handler, module})
        nil -> acc
      end
    end)
  end

  @component_handlers %{"cancel" => :cancel}
  defp component_handlers do
    @command_modules |> List.foldl(@component_handlers, fn module, acc ->
      case module.component_handlers() do
        {key, _} ->
          Map.put_new(acc, key, {:handler, module})
        nil ->
          acc
      end
    end)
  end

  @commands [
    %{name: "pingon",
      description_localizations: %{"ru" => "Включить роль для пингов в этом канале"},
      description: "Set role for pings in this channel"},
    %{name: "pingoff",
      description_localizations: %{"ru" => "Убрать роль для пингов в этом канале"},
      description: "Remove role for pings in this channel"},

    ]

  defp guild_application_commands(guild_id) do
    @command_modules |> List.foldl(@commands, fn module, acc ->
      [module.guild_application_command(guild_id) | acc]
    end)
  end

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  ###############################################################
  # handle events
  ###############################################################

  def handle_event({:GUILD_AVAILABLE, %{id: guild_id}, _ws_state}) do
    IO.puts "guild #{guild_id}"
    set_guild_commands(guild_id, guild_application_commands(guild_id))
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{type: 2}, _ws_state}) do
    path = extract_interaction_path(interaction)
    interaction_react(interaction, path)
  end

  def handle_event({:INTERACTION_CREATE, interaction = %{type: 3, data: %{custom_id: id}}, _ws_state}) do
    path = String.split(id, ":")
    component_react(interaction, path)
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

  def handle_event(event = {:CHANNEL_DELETE, _, _ws_state}) do
    @command_modules |> Enum.each(fn module -> module.handle_event(event) end)
  end

  def handle_event(event = {:VOICE_STATE_UPDATE, _, _ws_state}) do
    @command_modules |> Enum.each(fn module -> module.handle_event(event) end)
  end

  def handle_event({event, _, _}) do
    IO.inspect event
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  def component_react(interaction, path), do: component_react(interaction, path, component_handlers())
  def component_react(interaction, path = [name | rest], handlers) do
    case Map.get(handlers, name, nil) do
      nil ->
        Logger.warning "no handler for interaction #{inspect path} #{inspect handlers}~n#{inspect interaction}"
        DiscordHr.respond_to_component interaction, "Can't handle that, report to bot author"
      {:handler, module} ->
        Logger.debug "handling #{inspect path} in #{module}"
        module.component_react(interaction, rest)
      reaction when is_atom(reaction) ->
        handle_component(reaction, interaction, rest)
      more_handlers ->
        component_react(interaction, rest, more_handlers)
    end
  end

  def handle_component(:cancel, interaction, []) do
    DiscordHr.respond_to_component interaction, "Canceled"
  end


  ###############################################################
  # application commands
  ###############################################################

  def interaction_react(interaction, path), do: interaction_react(interaction, path, command_handlers())
  def interaction_react(interaction, path = [name | rest], handlers) do
    case Map.get(handlers, name, nil) do
      nil ->
        Logger.warning "no handler for interaction #{inspect path} #{inspect handlers}~n#{inspect interaction}"
        DiscordHr.respond_to_interaction interaction, "Can't handle that, report to bot author"
      {:handler, module} ->
        Logger.debug "handling #{inspect path} in #{module}"
        module.interaction_react(interaction, rest)
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

  def handle_application_command(:set_pingon, interaction = %{
    guild_id: guild_id, channel_id: channel_id,
    member: %{user: %{id: user_id, username: username}, roles: user_roles},
    data: %{name: "pingon"}
  }, _) do
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
      case roles |> Enum.find(fn ({_, %{name: name}}) -> name == channel_name end) do
        nil ->
          DiscordHr.respond_to_interaction interaction, "There's no ping role for this channel"
        {role_id, _} ->
          if Enum.member? user_roles, role_id do
            DiscordHr.respond_to_interaction interaction, "You already have role `@#{channel_name}`"
          else
            case Api.add_guild_member_role(guild_id, user_id, role_id, "#{username} used /pingme in #{channel_name}") do
              {:ok} ->
                DiscordHr.respond_to_interaction interaction, "Added `@#{channel_name}` role"
              {:error, %{response: %{message: message}}} ->
                DiscordHr.respond_to_interaction interaction, "Error: #{message}"
            end
          end
      end
    else
      _ -> DiscordHr.respond_to_interaction interaction, "Cannot find channel"
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
          DiscordHr.respond_to_interaction interaction, "There's no ping role for this channel"
        {role_id, _} ->
          if Enum.member? user_roles, role_id do
            case Api.remove_guild_member_role(guild_id, user_id, role_id, "#{username} used /pingme in #{channel_name}") do
              {:ok} ->
                DiscordHr.respond_to_interaction interaction, "Removed `@#{channel_name}` role"
              {:error, %{response: %{message: message}}} ->
                DiscordHr.respond_to_interaction interaction, "Error: #{message}"
            end
          else
              DiscordHr.respond_to_interaction interaction, "You don't have role `@#{channel_name}` set"
          end
      end
    else
      _ -> DiscordHr.respond_to_interaction interaction, "Cannot find channel"
    end
  end

  ###############################################################
  # helpers
  ###############################################################

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
