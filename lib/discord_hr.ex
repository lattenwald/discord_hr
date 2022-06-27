defmodule DiscordHr do
  alias Nostrum.Api
  require Logger

  use Bitwise, only_operators: true
  # https://discord.com/developers/docs/resources/channel#message-object-message-flags
  @flag_ephemeral 1 <<< 6

  def respond_to_interaction(interaction, text, components \\ nil) do
    case Api.create_interaction_response(interaction, %{type: 4, data: %{content: text, flags: @flag_ephemeral, components: components}}) do
      {:error, %{response: %{message: msg, errors: errors}}} ->
        Logger.error "error responding to interaction: '#{msg}' #{inspect errors}"
      {:error, err} ->
        Logger.error "error responding to interaction: #{inspect err}"
      {:ok} ->
        :ok
    end
  end

  def respond_to_component(interaction, text, components \\ []) do
    case Api.create_interaction_response(interaction, %{type: 7, data: %{content: text, components: components}}) do
      {:error, %{response: %{message: msg, errors: errors}}} ->
        Logger.error "error responding to component: '#{msg}' #{inspect errors}"
      {:error, err} ->
        Logger.error "error responding to component: #{inspect err}"
      {:ok} ->
        :ok
    end
  end

end
