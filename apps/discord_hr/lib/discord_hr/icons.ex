defmodule DiscordHr.Icons do
  use Agent

  def start_link(_) do
    {:ok, files} = File.ls "icons"
    files = files |> Enum.filter(&(Path.extname(&1) == ".jpg"))
    data = files |> Enum.map(fn file ->
      icon = "data:image/jpeg;base64," <> Base.encode64(File.read! "icons/#{file}")
      {String.downcase(Path.rootname(file)), icon}
    end) |> Enum.into(%{})
    Agent.start_link(fn -> data end, name: __MODULE__)
  end

  def list do
    Agent.get(__MODULE__, &Map.keys(&1))
  end

  def icon(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  def random do
    Agent.get(__MODULE__, &Enum.random(&1))
  end

end
