defmodule DiscordHr.Role do
  require Logger
  use DiscordHr.CommandModule

  alias DiscordHr.Storage
  alias Nostrum.Struct.Component
  alias Nostrum.Cache
  alias Nostrum.Api

  @key :roles_groups

  ###############################################################
  # callbacks
  ###############################################################

  @impl true
  def guild_application_command(guild_id) do
    group_names = Storage.get([guild_id, @key])
                  |> Enum.filter(fn {_, %{enabled: enabled}} -> enabled end)
                  |> Enum.map(fn {n, _} -> n end)
                  |> IO.inspect
    choices = group_names |> Enum.map(& %{name: &1, value: &1})

    %{name: "role",
      description: "Choose role",
      description_localizations: %{"ru" => "Выбрать роль"},
      options: [%{
        name: "group",
        description: "roles group",
        description_localizations: %{"ru" => "группа ролей"},
        type: 3, choices: choices, required: true
      }]}
  end

  @impl true
  def command_handlers do
    {"role", %{}}
  end

  @impl true
  def component_handlers do
    {"role", %{}}
  end

  @impl true
  def interaction_react(
    interaction = %{guild_id: guild_id, member: %{roles: user_roles}, locale: locale},
    [%{"group" => name}]
  ) do
    {text, placeholder, errtext} = case locale do
      "ru" <> _ ->
        { "Выберите роли из `#{name}`",
          "Выберите роли",
          "Пизда рулю, ошибка" }
      _ ->
        { "Set your `#{name}` roles",
          "Choose roles",
          "Stuff fucked up, something went wrong" }
    end
    with %{roles: group_roles, max: max, enabled: true} <- Storage.get([guild_id, @key, name]) do

      all_roles = Cache.GuildCache.get!(guild_id).roles
      options = group_roles
                |> Enum.sort_by(& all_roles[&1].position, &>=/2)
                |> Enum.map(& %Component.Option{label: all_roles[&1].name, value: &1, default: Enum.member?(user_roles, &1)})
      menu = Component.SelectMenu.select_menu("role:select:#{name}", placeholder: placeholder, options: options, min_values: 0, max_values: min(max, length(options)))
      menu_row = Component.ActionRow.action_row components: [menu]

      buttons_row = Component.ActionRow.action_row components: [Component.Button.interaction_button("Cancel", "cancel", style: 1)]

      DiscordHr.respond_to_interaction interaction, text, [menu_row, buttons_row]
    else
      _ ->
        DiscordHr.respond_to_interaction interaction, errtext
    end
  end

  @impl true
  def component_react(
    interaction = %{
      guild_id: guild_id,
      member: %{roles: user_roles, user: %{id: user_id, username: username}},
      locale: locale,
      data: %{values: values}
    }, ["select", name]) do
      group_roles = Storage.get([guild_id, @key, name, :roles]) |> MapSet.new
      user_roles = MapSet.new user_roles
      values = values |> Enum.map(&String.to_integer/1) |> MapSet.new
      add_roles = MapSet.difference values, user_roles
      remove_roles = group_roles |> MapSet.intersection(user_roles) |> MapSet.difference(values)
      Logger.debug "add roles: #{inspect add_roles}, remove roles: #{inspect remove_roles}"

      add_roles |> Enum.each(&Api.add_guild_member_role(guild_id, user_id, &1, "#{username} selected roles in group #{name}"))
      remove_roles |> Enum.each(&Api.remove_guild_member_role(guild_id, user_id, &1, "#{username} selected roles in group #{name}"))

      text = case locale do
        "ru" <> _ -> "Роли проставлены"
        _ -> "Roles set"
      end

      DiscordHr.respond_to_component interaction, text
  end

  def update_guild_application_command(guild_id) do
    with {:ok, commands} <- Api.get_guild_application_commands(guild_id),
         %{id: command_id} <- Enum.find(commands, fn %{name: name} -> name == "role" end)
    do
      command = guild_application_command(guild_id)
      case Api.edit_guild_application_command(guild_id, command_id, command) do
        {:error, %{status_code: 429, response: %{retry_after: retry_after}}} ->
          Logger.warning "failed setting guild application command for guild #{guild_id}, will retry in #{retry_after} seconds"
          :timer.apply_after(floor(retry_after * 1000) + 100, __MODULE__, :update_guild_application_command, [guild_id])
        {:error, %{response: %{message: message}}} ->
          retry_after = 10
          Logger.warning "failed setting guild application command for guild #{guild_id}: #{message} will retry in #{retry_after} seconds"
          :timer.apply_after(floor(retry_after * 1000) + 100, __MODULE__, :update_guild_application_command, [guild_id])
        {:ok, _} ->
          :ok
      end
    else
      _ -> :noop
    end
  end

end
