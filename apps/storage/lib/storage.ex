defmodule Storage do
  defmodule Voice do
    use Memento.Table, attributes: [:guild_id, :channel_id]

    def get(guild_id) do
      Memento.transaction fn -> Memento.Query.read(__MODULE__, guild_id) end
    end

    def get do
      Memento.transaction fn -> Memento.Query.all(__MODULE__) end
    end
  end

  def setup do
    nodes = [node()]
    Memento.stop
    Memento.Schema.create(nodes)
    Memento.start

    Memento.Table.create(Storage.Voice, disc_copies: nodes)
  end

  def delete(table, id) do
    Memento.transaction fn -> Memento.Query.delete(table, id) end
  end

  def write(record) do
    Memento.transaction fn -> Memento.Query.write(record) end
  end
end
