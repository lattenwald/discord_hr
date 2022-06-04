import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:file, :line]

try do
  import_config "secret.exs"
catch
  _, _ -> :missing
end
