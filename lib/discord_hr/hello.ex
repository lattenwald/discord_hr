defmodule DiscordHr.Hello do
  require Logger
  use DiscordHr.CommandModule

  @key :roles_groups

  alias DiscordHr.Storage
  alias Nostrum.Struct
  alias Nostrum.Struct.Component
  alias Nostrum.Cache

  @impl true
  def guild_application_command(_) do
    %{
      name: "hello",
      type: 1,
      description: "Say hello!",
      description_localizations: %{"ru" => "Поприветствуй воспитателя"}
    }
  end

  @impl true
  def command_handlers(), do: {"hello", %{}}

  @impl true
  def interaction_react(interaction = %{guild_id: guild_id}, []) do
    {text, components} = hello_components(interaction)
    DiscordHr.respond_to_interaction(interaction, text, components)
  end

  defp hello_components(%{guild_id: guild_id, locale: locale, member: %{roles: user_roles}}) do
    groups = Storage.get([guild_id, @key])
             |> Map.filter(fn {_, val} -> val.enabled and length(val.roles) > 0 end)
             |> Enum.sort_by(& elem(&1, 0))
    case groups do
      [] ->
        {"No groups yo", []} #FIXME translation
      _ ->
        all_roles = Cache.GuildCache.get!(guild_id).roles
        rows = groups
               |> Enum.map(fn {name, %{roles: group_roles, max: max}} ->
                 user_group_roles = user_roles |> Enum.filter(& Enum.member?(group_roles, &1)) |> Enum.take(max)
                 options = group_roles
                           |> Enum.sort_by(& all_roles[&1].position, &>=/2)
                           |> Enum.map(& %Component.Option{label: all_roles[&1].name, value: &1, default: Enum.member?(user_group_roles, &1)})
                 #FIXME translation
                 menu = Component.SelectMenu.select_menu("hello:select:#{name}", placeholder: "Select #{name} roles", options: options, min_values: 0, max_values: min(max, length(options)))
                 Component.ActionRow.action_row components: [menu]
               end)
        {"Choose your roles", rows}
    end
  end

end
