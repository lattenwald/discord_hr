defmodule DiscordHr.Storage do
  use Agent
  require Logger

  def start_link(storage) do
    {:ok, data} = load(storage)
    Agent.start_link(fn -> %{data: data, storage: storage} end, name: __MODULE__)
  end

  defp load(storage) do
    Logger.info("loading data from #{storage}")

    with {:ok, contents} <- File.read(storage),
         data <- :erlang.binary_to_term(contents) do
      {:ok, data}
    else
      {:error, :enoent} -> {:ok, %{}}
      error = {:error, _} -> error
      error -> {:error, error}
    end
  end

  defp save() do
    %{data: data, storage: storage} = Agent.get(__MODULE__, & &1)
    File.write!(storage, :erlang.term_to_binary(data))
  end

  def put(keys, value) when is_list(keys) do
    Agent.update(__MODULE__, &put_in_map(&1, [:data | keys], value))
    save()
  end

  def get(keys \\ [], default \\ nil) when is_list(keys) do
    case Agent.get(__MODULE__, &get_in(&1, [:data | keys])) do
      nil -> default
      other -> other
    end
  end

  def update(keys, fun) when is_list(keys) and is_function(fun) do
    Agent.update(__MODULE__, &update_in(&1, [:data | keys], fun))
    save()
  end

  def delete(keys) when is_list(keys) do
    Agent.update(__MODULE__, &delete_in_map(&1, [:data | keys]))
    save()
  end

  def delete_in_map(map, [key]) do
    Map.delete(map, key)
  end

  def delete_in_map(map, [key | rest]) do
    internal = Map.get(map, key, %{})
    Map.put(map, key, delete_in_map(internal, rest))
  end

  def put_in_map(map, [key], val), do: Map.put(map, key, val)

  def put_in_map(map, [key | rest], val) do
    internal = Map.get(map, key, %{})
    Map.put(map, key, put_in_map(internal, rest, val))
  end
end
