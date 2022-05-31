defmodule DiscordHr do
  alias Nostrum.Api

  use Bitwise, only_operators: true
  # https://discord.com/developers/docs/resources/channel#message-object-message-flags
  @flag_ephemeral 1 <<< 6

  def respond_to_interaction(interaction, text, components \\ nil) do
    Api.create_interaction_response(interaction, %{type: 4, data: %{content: text, flags: @flag_ephemeral, components: components}})
  end

  def respond_to_component(interaction, text, components \\ []) do
    Api.create_interaction_response(interaction, %{type: 7, data: %{content: text, components: components}})
  end

end
