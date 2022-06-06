defmodule DiscordHr.Ping do
  require Logger
  use DiscordHr.CommandModule

  alias Nostrum.Api
  alias Nostrum.Cache

  @impl true
  def guild_application_command(_) do
    %{
      name: "ping",
      description: "Manage ping role",
      description_localizations: %{"ru" => "Управление ролью для пингов в этом канале"},
      options: [
        %{
          name: "on",
          type: 1,
          description: "Add role for pings in this channel",
          description_localizations: %{"ru" => "Добавить роль для пингов в этом канале"},
        },
        %{
          name: "off",
          type: 1,
          description: "Remove role for pings in this channel",
          description_localizations: %{"ru" => "Убрать роль для пингов в этом канале"},
        }
      ]
    }
  end

  @impl true
  def command_handlers do
    {"ping", %{}}
  end

  @impl true
  def interaction_react(interaction = %{
    guild_id: guild_id, channel_id: channel_id, locale: locale,
    member: %{user: %{id: user_id, username: username}, roles: user_roles}
  }, ["on"]) do
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
      {text_norole, text_alreadyhave, text_ok} = case locale do
        "ru" <> _ ->
          { "Нет роли для пингов в этом канале",
            "У вас уже есть роль `@#{channel_name}`",
            "Добавлена роль `@#{channel_name}`" }
        _ ->
          { "There's no ping role for this channel",
            "You already have role `@#{channel_name}`",
            "Added `@#{channel_name}` role" }
      end

      case roles |> Enum.find(fn ({_, r}) -> r.name == channel_name and r.mentionable end) do
        nil ->
          DiscordHr.respond_to_interaction interaction, text_norole
        {role_id, _} ->
          if Enum.member? user_roles, role_id do
            DiscordHr.respond_to_interaction interaction, text_alreadyhave
          else
            case Api.add_guild_member_role(guild_id, user_id, role_id, "#{username} used /ping in #{channel_name}") do
              {:ok} ->
                DiscordHr.respond_to_interaction interaction, text_ok
              {:error, %{response: %{message: message}}} ->
                DiscordHr.respond_to_interaction interaction, "Error: #{message}"
            end
          end
      end
    else
      _ -> DiscordHr.respond_to_interaction interaction, "Cannot find channel"
    end
  end

  def interaction_react(interaction = %{
    guild_id: guild_id, channel_id: channel_id, locale: locale,
    member: %{user: %{id: user_id, username: username}, roles: user_roles}
  }, ["off"]) do
    with %{roles: roles, channels: %{^channel_id => %{name: channel_name}}} <- Cache.GuildCache.get!(guild_id) do
      {text_norole, text_donthave, text_ok} = case locale do
        "ru" <> _ ->
          { "Нет роли для пингов в этом канале",
            "У вас и не было роли `@#{channel_name}`",
            "Убрана роль `@#{channel_name}`" }
        _ ->
          { "There's no ping role for this channel",
            "You don't have role `@#{channel_name}`",
            "Removed `@#{channel_name}` role" }
      end
      case roles |> Enum.find(fn ({_, %{name: name}}) -> name == channel_name end) do
        nil ->
          DiscordHr.respond_to_interaction interaction, text_norole
        {role_id, _} ->
          if Enum.member? user_roles, role_id do
            case Api.remove_guild_member_role(guild_id, user_id, role_id, "#{username} used /ping in #{channel_name}") do
              {:ok} ->
                DiscordHr.respond_to_interaction interaction, text_ok
              {:error, %{response: %{message: message}}} ->
                DiscordHr.respond_to_interaction interaction, "Error: #{message}"
            end
          else
              DiscordHr.respond_to_interaction interaction, text_donthave
          end
      end
    else
      _ -> DiscordHr.respond_to_interaction interaction, "Cannot find channel"
    end
  end

end
