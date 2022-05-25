import Config

config :mnesia,
  dir: 'mnesia/#{Mix.env}/#{node()}'

try do
  import_config "secret.exs"
catch
  _, _ -> :missing
end
