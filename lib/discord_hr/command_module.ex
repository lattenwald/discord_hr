defmodule DiscordHr.CommandModule do
  defmacro __using__(_params) do
    quote do
      def command_handlers, do: nil
      def component_handlers, do: nil

      def guild_application_command(_), do: nil

      def handle_event(_), do: :noop

      def interaction_react(interaction, _) do
        DiscordHr.respond_to_interaction interaction, "Can't handle that in `#{__MODULE__}`, report to bot author"
      end

      def component_react(interaction, _) do
        DiscordHr.respond_to_component interaction, "Can't handle that in `#{__MODULE__}`, report to bot author"
      end

      defoverridable [command_handlers: 0, component_handlers: 0, guild_application_command: 1, handle_event: 1, interaction_react: 2, component_react: 2]
    end
  end
end
