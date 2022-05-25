defmodule Mix.Tasks.Setup do
  @moduledoc "Setup mnesia schema and tables"
  use Mix.Task

  @shortdoc "Calls Storage.setup"
  def run(_) do
    # calling our Hello.say() function from earlier
    Storage.setup()
  end
end
