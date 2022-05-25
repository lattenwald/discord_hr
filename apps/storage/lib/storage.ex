defmodule Storage do
  defmodule Voice do
    use Memento.Table, attributes: [:guild_id, :channel_id]

    def get(guild_id) do
      Memento.transaction fn -> Memento.Query.read(__MODULE__, guild_id) end
    end
  end

  def delete(table, id) do
    Memento.transaction fn -> Memento.Query.delete(table, id) end
  end

  def write(record) do
    Memento.transaction fn -> Memento.Query.write(record) end
  end
end
