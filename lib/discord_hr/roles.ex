defmodule DiscordHr.Roles do
  require Logger
  use DiscordHr.CommandModule

  alias DiscordHr.Storage
  alias Nostrum.Struct
  alias Nostrum.Struct.Component
  alias Nostrum.Cache
  alias Nostrum.Api

  @key :roles_groups
  @empty_group %{enabled: false, max: 1, roles: []}
  @max_name_length 10
  @name_regex ~r/^[a-z][a-z0-9_]*$/

  ###############################################################
  # callbacks
  ###############################################################

  @impl true
  def guild_application_command(guild_id) do
    groups = Storage.get([guild_id, @key])
    group_names = Map.keys groups
    choices = group_names |> Enum.map(& %{name: &1, value: &1})

    %{
      name: "adminroles",
      description: "Roles stuff",
      default_permission: false,
      options: [%{
        name: "groups",
        description: "Setup roles groups",
        type: 2,
        options: [%{
          name: "list",
          description: "List roles groups",
          type: 1
        }, %{
          name: "setup",
          description: "Setup role group",
          type: 1
        }, %{
          name: "add",
          description: "Add roles group",
          type: 1,
        }, %{
          name: "delete",
          description: "Delete roles groups",
          type: 1
        }, %{
          name: "rename",
          description: "Rename group",
          type: 1
        }]
        }]
      }
  end

  @impl true
  def command_handlers do
    {"adminroles", %{
      "groups" => %{
        "list" => :groups_list,
        "add" => :add_group,
        "delete" => :delete_group,
        "rename" => :rename_group,
        "setup" => :group_setup,
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
      }, "setup" => %{
        "select" => :setup_select,
        "next" => :setup_next,
        "prev" => :setup_prev,
      }, "input" => %{
        "add_name" => :add_name,
        "rename" => :rename_input,
      }, "add_name" => %{
        "do_setup" => :added_setup,
        "cancel_setup" => :added_nosetup
      }, "rename" => %{
        "select" => :rename_select,
        "button" => :rename_selected,
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

  ###############################################################
  # private
  ###############################################################

  defp handle_application_command(:groups_list, interaction = %{guild_id: guild_id}, []) do
    groups = Storage.get([guild_id, @key], %{})
    case map_size(groups) do
      0 ->
        DiscordHr.respond_to_interaction interaction, "No roles groups are set up"
      _ ->
        all_roles = Cache.GuildCache.get!(guild_id).roles
        text = groups
               |> Enum.zip(1 .. 1000)
               |> Enum.map(fn {{name, %{enabled: enabled, roles: roles, max: max}}, num} ->
                 roles_text = roles
                              |> Enum.map(&"    `#{all_roles[&1].name}`")
                              |> Enum.join("\n")
                 "#{num}. `#{name}` : **#{if enabled, do: "on", else: "off"}**, can select #{max} of #{length(roles)}\n" <> roles_text
               end)
               |> Enum.join("\n")
        DiscordHr.respond_to_interaction interaction, text
    end
  end

  defp handle_application_command(:add_group, interaction = %{guild_id: guild_id}, []) do
    input = Component.TextInput.text_input("Group name: ^[a-z][a-z0-9_]*$", "roles:input:add_name:name", min_length: 1, max_length: @max_name_length, required: true)
    row = Component.ActionRow.action_row components: [input]
    Api.create_interaction_response(interaction, %{type: 9, data: %{title: "Group name", custom_id: "roles:input:add_name", components: [row]}})
  end

  defp handle_application_command(:delete_group, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, @key], %{}) do
      empty when map_size(empty) == 0 ->
        DiscordHr.respond_to_interaction interaction, "No groups to delete"
      _ ->
        {text, components} = delete_group_components(guild_id)
        DiscordHr.respond_to_interaction interaction, text, components
    end
  end

  defp handle_application_command(:rename_group, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, @key], %{}) do
      empty when map_size(empty) == 0 ->
        DiscordHr.respond_to_interaction interaction, "No groups to rename"
      _ ->
        {text, components} = rename_group_components(guild_id)
        DiscordHr.respond_to_interaction interaction, text, components
    end
  end

  defp handle_application_command(:group_setup, interaction = %{guild_id: guild_id}, []) do
    case Storage.get([guild_id, @key], %{}) do
      empty when map_size(empty) == 0 ->
        DiscordHr.respond_to_interaction interaction, "No groups to setup"
      _ ->
        {text, components} = setup_group_components(guild_id)
        DiscordHr.respond_to_interaction interaction, text, components
    end
  end

  defp handle_component(:rename_select, interaction = %{guild_id: guild_id, data: %{values: selected}}, []) do
    {text, components} = rename_group_components(guild_id, selected)
    DiscordHr.respond_to_component(interaction, text, components)
  end

  defp handle_component(:rename_selected, interaction, []) do
    [name] = components_selected(interaction)["roles:rename:select"]
    input = Component.TextInput.text_input("Renaming `#{name}`", "roles:input:rename", min_length: 1, max_length: @max_name_length, required: true)
    row = Component.ActionRow.action_row components: [input]
    Api.create_interaction_response(interaction, %{type: 9, data: %{title: "Renaming `#{name}`", custom_id: "roles:input:rename:#{name}", components: [row]}})
  end

  defp handle_component(:rename_input, interaction = %{guild_id: guild_id}, old_name) do
    old_name = Enum.join(old_name, ":")
    new_name = get_input(interaction)["roles:input:rename"] |> IO.inspect
    case validate_group_name(guild_id, new_name) do
      {:error, msg} ->
        DiscordHr.respond_to_interaction interaction, msg
      :ok ->
        {group, groups} = Storage.get([guild_id, @key]) |> Map.pop!(old_name)
        groups = groups |> Map.put_new(new_name, group)
        Storage.put [guild_id, @key], groups
        DiscordHr.respond_to_component interaction, "Group `#{old_name}` renamed to `#{new_name}`"
        DiscordHr.Role.update_guild_application_command guild_id
    end
  end

  defp handle_component(:group_delete_select, interaction = %{guild_id: guild_id, data: %{values: selected}}, []) do
    {text, components} = delete_group_components(guild_id, selected)
    DiscordHr.respond_to_component(interaction, text, components)
  end

  defp handle_component(:group_delete_button, interaction = %{guild_id: guild_id}, []) do
    names = components_selected(interaction)["roles:delete:select"]
    names |> Enum.each(& Storage.delete [guild_id, @key, &1])
    deleted = names |> Enum.zip(1..1000) |> Enum.map(fn {n, i} -> "  #{i}. `#{n}`" end) |> Enum.join("\n")
    DiscordHr.respond_to_component interaction, "Deleted roles groups:\n#{deleted}"
    DiscordHr.Role.update_guild_application_command guild_id
  end

  defp handle_component(:add_name, interaction = %{guild_id: guild_id}, []) do
    values = get_input(interaction)
    name = values["roles:input:add_name:name"] |> String.trim |> String.downcase


    case validate_group_name(guild_id, name) do
      {:error, msg} ->
        DiscordHr.respond_to_interaction interaction, msg
      :ok ->
        Storage.put([guild_id, @key, name], @empty_group)

        buttons = Component.ActionRow.action_row components: [
          Component.Button.interaction_button("Cancel", "roles:add_name:cancel_setup:#{name}", style: 1),
          Component.Button.interaction_button("Setup", "roles:add_name:do_setup:#{name}")
        ]

        DiscordHr.respond_to_interaction interaction, "Group `#{name}` added, setup it now?", [buttons]
    end
  end

  defp handle_component(:added_setup, interaction = %{guild_id: guild_id}, name) do
    name = Enum.join(name, ":")
    {text, components} = setup_group_components(guild_id, name, 1)
    DiscordHr.respond_to_component interaction, text, components
  end

  defp handle_component(:added_nosetup, interaction = %{guild_id: guild_id}, name) do
    name = Enum.join(name, ":")
    DiscordHr.respond_to_component interaction, "Group `#{name}` added"
  end

  defp handle_component(:group_toggle_button,
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

  defp handle_component(:setup_select, interaction = %{
    guild_id: guild_id,
    data: %{values: values}
  }, [step | rest]) do
    {step, ""} = Integer.parse step
    name = Enum.join rest, ":"
    values = fix_values(values, step)
    {text, components} = setup_group_components(guild_id, name, step, values)
    DiscordHr.respond_to_component interaction, text, components
  end

  defp handle_component(:setup_next, interaction = %{
    guild_id: guild_id,
    message: %{components: components}
  }, path = [step | rest]) do
    {step, ""} = Integer.parse step
    menu_id = "roles:setup:select:" <> Enum.join(path, ":")
    selected = components_selected(components)
    values = selected[menu_id] |> fix_values(step)
    name = case step do
      0 -> hd(values)
      _ ->Enum.join rest, ":"
    end

    save_progress(step, guild_id, name, values)

    {text, components} = setup_group_components(guild_id, name, step+1)
    DiscordHr.respond_to_component interaction, text, components
  end

  defp handle_component(:setup_prev, interaction = %{
    guild_id: guild_id
  }, [step | rest]) do
    {step, ""} = Integer.parse step
    name = Enum.join rest, ":"
    {text, components} = setup_group_components(guild_id, name, step-1)
    DiscordHr.respond_to_component interaction, text, components
  end

  defp get_input(%Struct.Interaction{data: %{components: components}}) do
    components_selected(components)
  end

  defp components_selected(%Struct.Interaction{message: %{components: components}}), do: components_selected(components)
  defp components_selected(nil), do: %{}
  defp components_selected([]), do: %{}
  defp components_selected(components = [_|_]), do: components_selected(components, %{})
  defp components_selected([], acc), do: acc
  defp components_selected([comp|rest], acc) do
    acc = case comp do
      %{type: 3, custom_id: id, options: options} ->
        selected = (options || []) |> Enum.filter(&Map.get(&1, :default, false)) |> Enum.map(& &1.value)
        acc |> Map.put(id, selected)
      %{type: 4, custom_id: id, value: value} ->
        acc |> Map.put(id, value)
      %{type: 1, components: components} ->
        row_data = components_selected(components)
        acc |> Map.merge(row_data)
      %{} ->
        acc
    end
    components_selected(rest, acc)
  end

  defp fix_values(step, values) when is_binary(step), do: fix_values(String.to_integer(step), values)
  defp fix_values(values, 1), do: Enum.map(values, &String.to_integer/1)
  defp fix_values(["False"], 3), do: false
  defp fix_values(["True"], 3), do: true
  defp fix_values(values, _), do: values

  defp save_progress(0, _, _, _), do: :noop
  defp save_progress(1, guild_id, name, roles) do
    Storage.put([guild_id, @key, name, :roles], roles)
  end
  defp save_progress(2, guild_id, name, [max]) do
    {max, ""} = Integer.parse max
    Storage.put([guild_id, @key, name, :max], max)
  end
  defp save_progress(2, _, _, []), do: :noop
  defp save_progress(3, guild_id, name, enabled) do
    prev = Storage.get([guild_id, @key, name, :enabled], nil)
    Storage.put([guild_id,  @key, name, :enabled], enabled)
    if prev != enabled do
      DiscordHr.Role.update_guild_application_command guild_id
    end
  end

  defp setup_group_components(guild_id), do: setup_group_components(guild_id, nil, 0)

  defp setup_group_components(guild_id, name), do: setup_group_components(guild_id, name, 1)
  defp setup_group_components(guild_id, name, step), do: setup_group_components(guild_id, name, step, nil)

  defp setup_group_components(guild_id, _, step = 0, selected) do
    case Storage.get([guild_id, @key]) |> Map.keys do
      [name] -> setup_group_components(guild_id, name, 1)
      names ->
        text = "Choose roles group to setup"
        options = names |> Enum.map(& %Component.Option{label: &1, value: &1, default: [&1] == selected})
        menu = Component.SelectMenu.select_menu("roles:setup:select:#{step}:", placeholder: "Choose group", options: options, min_values: 1, max_values: 1)
        menu_row = Component.ActionRow.action_row components: [menu]
        buttons = Component.ActionRow.action_row components: [
          Component.Button.interaction_button("<<", "none", disabled: true),
          Component.Button.interaction_button(">>", "roles:setup:next:#{step}:")
        ]
        {text, [menu_row, buttons]}
    end
  end

  defp setup_group_components(guild_id, name, step = 1, selected) do
    text = "Roles group `#{name}`\nChoose roles"

    roles = Storage.get([guild_id, @key, name, :roles], [])
    all_roles = Cache.GuildCache.get!(guild_id).roles |> Enum.filter(fn {_, r} -> !r.managed and r.name != "@everyone" end)
    options = all_roles |> Enum.map(fn {id, %{name: n}} ->
      %Component.Option{label: n, value: id, default: Enum.member?((selected || roles), id)}
    end)
    menu = Component.SelectMenu.select_menu("roles:setup:select:#{step}:#{name}", placeholder: "Choose roles", options: options, min_values: 0, max_values: min(20, length(options)))
    menu_row = Component.ActionRow.action_row components: [menu]

    buttons = Component.ActionRow.action_row components: [
      Component.Button.interaction_button("<<", "roles:setup:prev:#{step}:#{name}"),
      Component.Button.interaction_button(">>", "roles:setup:next:#{step}:#{name}")
    ]

    {text, [menu_row, buttons]}
  end

  defp setup_group_components(guild_id, name, step = 2, selected) do
    all_roles = Cache.GuildCache.get!(guild_id).roles
    %{roles: roles, max: max} = Storage.get([guild_id, @key, name])
    roles_text = roles
                 |> Enum.map(&"    `#{all_roles[&1].name}`")
                 |> Enum.join("\n")

    text = "Roles group `#{name}`\n#{roles_text}\nChoose max selectable roles"

    menu = Component.SelectMenu.select_menu("roles:setup:select:#{step}:#{name}",
      placeholder: "#{max}",
      options: 1 .. max(1, length(roles)) |> Enum.map(& %Component.Option{label: "#{&1}", value: &1, default: ("#{selected}" || "#{max}") == "#{&1}"})
    )
    menu_row = Component.ActionRow.action_row components: [menu]
    buttons = Component.ActionRow.action_row components: [
      Component.Button.interaction_button("<<", "roles:setup:prev:#{step}:#{name}"),
      Component.Button.interaction_button(">>", "roles:setup:next:#{step}:#{name}")
    ]

    {text, [menu_row, buttons]}
  end

  defp setup_group_components(guild_id, name, step = 3, selected) do
    all_roles = Cache.GuildCache.get!(guild_id).roles
    %{roles: roles, max: max, enabled: enabled} = Storage.get([guild_id, @key, name])
    roles_text = roles
                 |> Enum.map(&"    `#{all_roles[&1].name}`")
                 |> Enum.join("\n")

    text = "Roles group `#{name}`\n#{roles_text}\nMax `#{max}` roles selectable\nEnable?"

    default = case selected do
      nil -> enabled
      _ -> selected
    end
    menu = Component.SelectMenu.select_menu("roles:setup:select:#{step}:#{name}",
      placeholder: "enable?",
      options: [
        %Component.Option{label: "on", value: true, default: default},
        %Component.Option{label: "off", value: false, default: !default},
      ]
    )
    menu_row = Component.ActionRow.action_row components: [menu]
    buttons = Component.ActionRow.action_row components: [
      Component.Button.interaction_button("<<", "roles:setup:prev:#{step}:#{name}"),
      Component.Button.interaction_button(">>", "roles:setup:next:#{step}:#{name}")
    ]

    {text, [menu_row, buttons]}
  end

  defp setup_group_components(guild_id, name, step = 4, _) do
    all_roles = Cache.GuildCache.get!(guild_id).roles
    %{roles: roles, max: max, enabled: enabled} = Storage.get([guild_id, @key, name])
    roles_text = roles
                 |> Enum.map(&"    `#{all_roles[&1].name}`")
                 |> Enum.join("\n")

    text = "Roles group `#{name}`\n#{roles_text}\nMax `#{max}` roles selectable\nenabled: **#{if enabled, do: "yes", else: "no"}**"

    buttons = Component.ActionRow.action_row components: [
      Component.Button.interaction_button("<<", "roles:setup:prev:#{step}:#{name}"),
      Component.Button.interaction_button("Done!", "roles:setup:next:#{step}:#{name}", disabled: true)
    ]

    {text, [buttons]}
  end

  defp delete_group_components(guild_id), do: delete_group_components(guild_id, [])
  defp delete_group_components(guild_id, selected) do
    names = Storage.get([guild_id, @key]) |> Map.keys
    text = "Choose roles groups to delete"
    options = names |> Enum.map(& %Component.Option{label: &1, value: &1, default: Enum.member?(selected, &1)})
    menu = Component.SelectMenu.select_menu("roles:delete:select", placeholder: "Choose groups to delete", options: options, min_values: 1, max_values: min(10, length(names)))
    menu_row = Component.ActionRow.action_row components: [menu]
    buttons = Component.ActionRow.action_row components: [
      Component.Button.interaction_button("DELETE", "roles:delete:button", style: 4, disabled: selected == []),
      Component.Button.interaction_button("Cancel", "cancel", style: 1)
    ]
    {text, [menu_row, buttons]}
  end

  defp rename_group_components(guild_id), do: rename_group_components(guild_id, [])
  defp rename_group_components(guild_id, selected) do
    names = Storage.get([guild_id, @key]) |> Map.keys
    text = "Choose roles group to rename"
    options = names |> Enum.map(& %Component.Option{label: &1, value: &1, default: [&1] == selected})
    menu = Component.SelectMenu.select_menu("roles:rename:select", placeholder: "Choose group to rename", options: options, min_values: 1, max_values: 1)
    menu_row = Component.ActionRow.action_row components: [menu]
    buttons = Component.ActionRow.action_row components: [
      Component.Button.interaction_button("Rename", "roles:rename:button", style: 1, disabled: selected == []),
      Component.Button.interaction_button("Cancel", "cancel", style: 1)
    ]
    {text, [menu_row, buttons]}
  end

  defp validate_group_name(guild_id, name) do
    existing = Storage.get([guild_id, @key]) |> Map.keys
    cond do
      String.length(name) > @max_name_length ->
        {:error, "Group name is too long, shouldn't exceed #{@max_name_length} characters"}
      not String.match? name, @name_regex ->
        {:error, "Group name `#{name}` is invalid: should consist of latin letter, numbers and underscore, starting with letter"}
      Enum.member?(existing, name) ->
        {:error, "Group with name `#{name}` is already present"}
      true ->
        :ok
    end
  end

end
