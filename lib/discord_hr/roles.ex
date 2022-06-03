defmodule DiscordHr.Roles do
  require Logger
  use DiscordHr.CommandModule

  alias DiscordHr.Storage
  alias Nostrum.Struct.Component
  alias Nostrum.Cache

  @key :roles_groups
  @empty_group %{enabled: false, max: 1, roles: []}

  @command %{
    name: "roles",
    description: "Roles stuff",
    options: [%{
      name: "groups",
      description: "Setup roles groups",
      type: 2,
      default_member_permission: "0",
      options: [%{
        name: "list",
        description: "List roles groups",
        type: 1
      }, %{
        name: "add",
        description: "Add roles group",
        type: 1,
        options: [%{
          name: "name",
          description: "name",
          type: 3,
          required: true
        }]
      }, %{
        name: "delete",
        description: "Delete roles groups",
        type: 1
      }, %{
        name: "enable",
        description: "Enable roles groups",
        type: 1
      }, %{
        name: "disable",
        description: "Disable roles groups",
        type: 1
      }, %{
        name: "max_roles",
        description: "Setup max roles count for a roles group",
        type: 1
      }, %{
        name: "choose",
        description: "Set roles for a group",
        type: 1
      }]
    }, %{
      name: "test",
      description: "test",
      type: 1
    }]
  }
  @impl true
  def guild_application_command(_), do: @command

  @impl true
  def command_handlers do
    {"roles", %{
      "groups" => %{
        "list" => :groups_list,
        "add" => :add_group,
        "delete" => :delete_group,
        "enable" => :enable_groups,
        "disable" => :disable_groups,
        "max_roles" => :set_max_roles,
        "choose" => :choose_group_roles,
      }
    }}
  end

  @impl true
  def component_handlers do
    {"roles",
      %{"delete" => %{
        "select" => :group_delete_select,
        "button" => :group_delete_button,
      },"toggle" => %{
        "select" => :group_toggle_select,
        "button" => :group_toggle_button
      },"choose" => %{
        "select" => :group_choose_select,
        "button" => %{
          "set_max_roles" => :set_max_roles_selected,
          "choose_group_roles" => :set_group_roles_button,
        }
      }, "max_count" => %{
        "select" => :max_count_select
      }, "choose_roles" => %{
        "select" => :select_group_roles
      }
      }}
  end

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
        Logger.debug "handling component with #{inspect reaction} #{inspect rest}"
        handle_component(reaction, interaction, rest)
      more_handlers ->
        component_react(interaction, rest, more_handlers)
    end
  end

  def handle_application_command(:groups_list, interaction = %{guild_id: guild_id}, []) do
    groups = Storage.get([guild_id, @key], %{})
    case map_size(groups) do
      0 ->
        DiscordHr.respond_to_interaction interaction, "No roles groups are set up"
      _ ->
        text = groups
               |> Enum.zip(1 .. 1000)
               |> Enum.map(fn {{name, %{enabled: enabled, roles: roles, max: max}}, num} ->
                 "#{num}. `#{name}` [#{max}/#{length(roles)}] **#{if enabled, do: "on", else: "off"}**"
               end)
               |> Enum.join("\n")
        DiscordHr.respond_to_interaction interaction, text
    end
  end

  def handle_application_command(:add_group, interaction = %{guild_id: guild_id}, [%{"name" => name}]) do
    groups = Storage.get([guild_id, @key], %{})
    if Map.has_key?(groups, name) do
      DiscordHr.respond_to_interaction interaction, "Group with this name is already present"
    else
      groups = Map.put(groups, name, @empty_group)
      Storage.put([guild_id, @key], groups)
      DiscordHr.respond_to_interaction interaction, "Group `#{name}` added"
    end
  end

  def handle_application_command(:delete_group, interaction = %{guild_id: guild_id}, []) do
    components = delete_group_components(guild_id)
    DiscordHr.respond_to_interaction interaction, "Remove roles group", components
  end

  def handle_application_command(:enable_groups, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, @key], %{}) |> Enum.filter(fn {_, group} -> !group.enabled end) do
      [] -> DiscordHr.respond_to_interaction interaction, "All existing roles groups are enabled"
      _ ->
        components = toggle_group_components(guild_id, true)
        DiscordHr.respond_to_interaction interaction, "Enable roles group", components
    end
  end

  def handle_application_command(:disable_groups, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, @key], %{}) |> Enum.filter(fn {_, group} -> group.enabled end) do
      [] -> DiscordHr.respond_to_interaction interaction, "All existing roles groups are disabled"
      _ ->
        components = toggle_group_components(guild_id, false)
        DiscordHr.respond_to_interaction interaction, "Disable roles group", components
    end
  end

  def handle_application_command(:set_max_roles, interaction = %{guild_id: guild_id}, []) do
    case map_size Storage.get([guild_id, @key], %{}) do
      0 -> DiscordHr.respond_to_interaction interaction, "No roles group here"
      _ ->
        components = choose_group_components(guild_id, :set_max_roles)
        DiscordHr.respond_to_interaction interaction, "Choose group", components
    end
  end

  def handle_application_command(:choose_group_roles, interaction = %{guild_id: guild_id}, []) do
    case map_size Storage.get([guild_id, @key], %{}) do
      0 -> DiscordHr.respond_to_interaction interaction, "No roles group here"
      _ ->
        components = choose_group_components(guild_id, :choose_group_roles)
        DiscordHr.respond_to_interaction interaction, "Choose group", components
    end
  end


  def handle_component(:group_delete_select, interaction = %{guild_id: guild_id, data: %{values: selected}}, []) do
    components = delete_group_components(guild_id, selected)
    DiscordHr.respond_to_component interaction, "", components
  end

  def handle_component(:group_delete_button,
    interaction = %{
      guild_id: guild_id,
      message: %{
        components: [%{
          components: [%{
            custom_id: "roles:delete:select",
            options: options
          }]
        } | _]
      }
    }, [])
  do
    with remove <- options |> Enum.filter(& Map.get(&1, :default, false)) |> Enum.map(& &1.value) do
      groups = Storage.get([guild_id, @key], %{})
      new_groups = remove |> List.foldl(groups, &Map.delete(&2, &1))
      Storage.put([guild_id, @key], new_groups)
      DiscordHr.respond_to_component interaction, "Removed **#{map_size(groups) - map_size(new_groups)}** groups"
    else
      _ ->
        DiscordHr.respond_to_component interaction, "nothing to delete"
    end
  end

  def handle_component(:group_toggle_select, interaction = %{guild_id: guild_id, data: %{values: selected}}, [enable]) do
    enable = case enable do
      "on" -> true
      "off" -> false
    end
    components = toggle_group_components(guild_id, enable, selected)
    DiscordHr.respond_to_component interaction, "", components
  end

  def handle_component(:group_choose_select, interaction = %{guild_id: guild_id, data: %{values: [selected]}}, [type]) do
    components = choose_group_components(guild_id, type, selected)
    DiscordHr.respond_to_component interaction, "", components
  end


  def handle_component(:group_toggle_button,
    interaction = %{
      guild_id: guild_id,
      message: %{
        components: [%{
          components: [%{
            custom_id: "roles:toggle:select:" <> enable,
            options: options
          }]
        } | _]
      }
    }, [])
  do
    enable = case enable do
      "on" -> true
      "off" -> false
    end
    with toggle <- options |> Enum.filter(& Map.get(&1, :default, false)) |> Enum.map(& &1.value) do
      groups = Storage.get([guild_id, @key], %{})
      new_groups = toggle |> List.foldl(groups, &put_in(&2, [&1, :enabled], enable))
      Storage.put([guild_id, @key], new_groups)
      DiscordHr.respond_to_component interaction, "#{if enable, do: "Enabled", else: "Disabled"} **#{length(toggle)}** groups"
    else
      _ ->
        DiscordHr.respond_to_component interaction, "nothing to #{if enable, do: "enable", else: "disable"}"
    end
  end

  def handle_component(:set_max_roles_selected,
    interaction = %{
      guild_id: guild_id,
      message: %{components: components}
    }, [])
  do
    %{options: options} = find_component(components, "roles:choose:select:set_max_roles")
    name = Enum.find(options, &Map.get(&1, :default, :false)).value

    %{options: options} = find_component(components, "roles:max_count:select")
    value = Enum.find(options, &Map.get(&1, :default, :false)).value
    {value, ""} = Integer.parse(value)

    Storage.put([guild_id, @key, name, :max], value)
    DiscordHr.respond_to_component interaction, "Set max of `#{value}` roles for `#{name}` group", []
  end

  def handle_component(:set_group_roles_button,
    interaction = %{
      guild_id: guild_id,
      message: %{components: components}
    }, [])
  do
  %{options: options} = find_component(components, "roles:choose:select:choose_group_roles")
    name = Enum.find(options, &Map.get(&1, :default, :false)).value

    %{options: options} = find_component(components, "roles:choose_roles:select")
    values = options |> Enum.filter(&Map.get(&1, :default, false)) |> Enum.map(fn v ->
      {id, ""} = Integer.parse(v.value)
      id
    end)

    Storage.put([guild_id, @key, name, :roles], values)
    DiscordHr.respond_to_component interaction, "Set `#{length values}` roles for `#{name}` group", []
  end

  def handle_component(:max_count_select, interaction =
    %{guild_id: guild_id,
      message: %{components: components},
      data: %{values: [count]}
    }, []
  ) do
    {count, ""} = Integer.parse count
    %{options: options} = find_component(components, "roles:choose:select:set_max_roles")
    name = Enum.find(options, &Map.get(&1, :default, :false)).value

    components = choose_group_components(guild_id, :set_max_roles, name, count)
    DiscordHr.respond_to_component(interaction, "", components)
  end

  def handle_component(:select_group_roles, interaction =
    %{guild_id: guild_id,
      message: %{components: components},
      data: %{values: values}
    }, []
  ) do
    values = Enum.map(values, fn v ->
      {id, ""} = Integer.parse v
      id
    end)
    %{options: options} = find_component(components, "roles:choose:select:choose_group_roles")
    name = Enum.find(options, &Map.get(&1, :default, :false)).value

    components = choose_group_components(guild_id, :choose_group_roles, name, values)
    DiscordHr.respond_to_component(interaction, "", components)
  end


  defp delete_group_components(guild_id, selected \\ []) do
    groups = Storage.get([guild_id, @key], %{})
    options = groups |> Enum.map(fn {name, %{enabled: enabled}} ->
      %Component.Option{label: "#{name} [#{if enabled, do: "on", else: "off"}]", value: "#{name}", default: Enum.member?(selected, name)}
    end)
    menu = Component.SelectMenu.select_menu("roles:delete:select",
      placeholder: "Select groups to delete",
      min_values: 0,
      max_values: min(length(options), 20),
      options: options)
    row1 = Component.ActionRow.action_row()
    row1 = Component.ActionRow.put row1, menu
    [
      row1,
      Component.ActionRow.action_row([
        Component.Button.interaction_button("DELETE", "roles:delete:button", style: 4, disabled: selected == []),
        Component.Button.interaction_button("Cancel", "cancel", style: 1),
      ])
    ]
  end

  defp toggle_group_components(guild_id, enable, selected \\ []) do
    groups = Storage.get([guild_id, @key], %{}) |> Enum.filter(fn {_, group} -> group.enabled != enable end) |> Enum.into(%{})
    options = groups |> Enum.map(fn {name, _} ->
      %Component.Option{label: "#{name}", value: "#{name}", default: Enum.member?(selected, name)}
    end)
    menu = Component.SelectMenu.select_menu("roles:toggle:select:#{if enable, do: "on", else: "off"}",
      placeholder: "Select groups to #{if enable, do: "enable", else: "disable"}",
      min_values: 0,
      max_values: min(length(options), 20),
      options: options)
    row1 = Component.ActionRow.action_row()
    row1 = Component.ActionRow.put row1, menu
    [
      row1,
      Component.ActionRow.action_row([
        Component.Button.interaction_button((if enable, do: "Enable", else: "Disable"), "roles:toggle:button", style: 4, disabled: selected == []),
        Component.Button.interaction_button("Cancel", "cancel", style: 1),
      ])
    ]
  end

  def choose_group_components(guild_id, type, selected \\ nil, value \\ nil) do
    type = case type do
      _ when is_atom(type) -> type
      _ when is_binary(type) -> String.to_atom type
    end
    groups = Storage.get([guild_id, @key], %{})
    options = groups |> Enum.map(fn {name, _} ->
      %Component.Option{label: "#{name}", value: "#{name}", default: selected == name}
    end)
    menu = Component.SelectMenu.select_menu("roles:choose:select:#{type}",
      placeholder: "Select group",
      options: options)
    row1 = Component.ActionRow.action_row()
    row1 = Component.ActionRow.put row1, menu
    List.flatten [
      row1,
      second_component_row(type, guild_id, selected, value),
      Component.ActionRow.action_row([
        button(type, selected, value),
        Component.Button.interaction_button("Cancel", "cancel", style: 1),
      ])
    ]
  end

  defp button(_, nil, _), do: Component.Button.interaction_button("Choose role", "none", style: 4, disabled: true)
  defp button(:set_max_roles, _, nil), do: Component.Button.interaction_button("Choose max", "none", style: 4, disabled: true)
  defp button(:set_max_roles, name, value), do: Component.Button.interaction_button("Set #{value} for #{name}", "roles:choose:button:set_max_roles", style: 4)
  defp button(type = :choose_group_roles, name, nil), do: Component.Button.interaction_button("Set roles for #{name}", "roles:choose:button:#{type}", style: 4)
  defp button(type = :choose_group_roles, name, values), do: Component.Button.interaction_button("Set #{length(values)} roles for #{name}", "roles:choose:button:#{type}", style: 4)
  defp button(type, _, _), do: Component.Button.interaction_button("Choose role", "roles:choose:button:#{type}", style: 4)

  defp second_component_row(:set_max_roles, _, nil, _), do: []
  defp second_component_row(:set_max_roles, guild_id, name, value) do
    max = Storage.get([guild_id, @key]) |> get_in([name, :max])
    menu = Component.SelectMenu.select_menu("roles:max_count:select",
      placeholder: "#{max}",
      options: 1 .. 10 |> Enum.map(& %Component.Option{label: "#{&1}", value: &1, default: ("#{value}" || "#{max}") == "#{&1}"})
    )
    Component.ActionRow.action_row components: [menu]
  end
  defp second_component_row(:choose_group_roles, _, nil, _), do: []
  defp second_component_row(:choose_group_roles, guild_id, name, values) do
    values = case values do
      nil -> Storage.get([guild_id, @key, name, :roles])
      _ -> values
    end
    all_roles = Cache.GuildCache.get!(guild_id).roles |> Enum.filter(fn {_, r} -> !r.managed and r.name != "@everyone" end)
    options = all_roles |> Enum.map(fn {id, %{name: n}} ->
      %Component.Option{label: n, value: id, default: Enum.member?(values, id)}
    end)
    menu = Component.SelectMenu.select_menu("roles:choose_roles:select", placeholder: "Choose roles", options: options, min_values: 0, max_values: min(10, length(options)))
    row1 = Component.ActionRow.action_row
    row1 = Component.ActionRow.put row1, menu
    row1
  end
  defp second_component_row(type,_,_,_) do
    Logger.warning "second_component_row not defined for type #{inspect type}"
    []
  end

  defp find_component(nil, _), do: nil
  defp find_component([], _), do: nil
  defp find_component(components = [_|_], custom_id) do
    components |> Enum.find_value(&find_component(&1, custom_id))
  end
  defp find_component(component = %{custom_id: custom_id}, custom_id), do: component
  defp find_component(%{components: components}, custom_id) do
    find_component(components, custom_id)
  end

  @impl true
  def handle_event({:GUILD_ROLE_DELETE, {guild_id, %{id: role_id}}, _ws_state}) do
    fun = fn data ->
      case Map.get(data, @key) do
        nil -> data
        groups = %{} ->
          new_groups = groups
                       |> Enum.map(fn {group_name, group} ->
                         {group_name, Map.update(group, :roles, [], fn roles -> roles |> Enum.filter(& &1 != role_id) end)}
                       end)
                       |> Enum.into(%{})
          Map.put(data, @key, new_groups)
      end
    end

    Storage.update [guild_id], fun
  end
  def handle_event(_), do: :noop

end
