defmodule DiscordHr.Guilds do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def new_guild(guild = %{id: guild_id}) do
    Agent.update(__MODULE__, &Map.put_new(&1, guild_id, guild))
  end


  def role_created(guild_id, role = %{id: role_id}) do
    Agent.update(__MODULE__, &put_in(&1, [guild_id, Access.key(:roles), role_id], role))
  end

  def role_deleted(guild_id, %{id: role_id}) do
    Agent.update(__MODULE__, &update_in(&1, [guild_id, Access.key(:roles)], fn roles -> Map.delete(roles, role_id) end))
  end

  def role_updated(guild_id, role = %{id: role_id}) do
    Agent.update(__MODULE__, &update_in(&1, [guild_id, Access.key(:roles), role_id], fn old -> Map.merge(old, role) end))
  end


  def channel_updated(channel = %{guild_id: guild_id, id: channel_id}) do
    Agent.update(__MODULE__, &put_in(&1, [guild_id, Access.key(:channels), channel_id], channel))
  end

  def channel_deleted(%{guild_id: guild_id, id: channel_id}) do
    Agent.update(__MODULE__, &update_in(&1, [guild_id, Access.key(:channels)], fn channels -> Map.delete(channels, channel_id) end))
  end


  def get do
    Agent.get(__MODULE__, & &1)
  end

  def get(id) do
    Agent.get(__MODULE__, & &1[id])
  end
end
