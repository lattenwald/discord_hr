import Config

try do
  import_config "secret.exs"
catch
  _, _ -> :missing
end
