defmodule DiscordHr.VoiceClaim do
  require Logger
  use DiscordHr.CommandModule

  alias DiscordHr.Storage
  alias Nostrum.Cache
  alias Nostrum.Api

  @impl true
  def guild_application_command(_) do
    %{
      name: "claim",
      description: "Claim unclaimed voice channel",
      description_localizations: %{"ru" => "Забрать ничейный голосовой канал"}
    }
  end

  @impl true
  def command_handlers() do
    {"claim", %{}}
  end

  @impl true
  def interaction_react(interaction = %{
    guild_id: guild_id,
    member: %{user: %{id: userid, username: username}},
    locale: locale
  }, _) do
    try do
      default_voice = Storage.get([guild_id, :default_voice])
      if default_voice == nil, do: throw({"Voice not set up", "Голосовой канал не настроен"})

      {:ok, %{parent_id: parent_id}} = Cache.ChannelCache.get(default_voice)
      {:ok, %{channels: channels, voice_states: voice_states}} = Cache.GuildCache.get(guild_id)

      channel_id = case voice_states |> Enum.find(& &1.user_id == userid) do
        %{channel_id: channel_id} -> channel_id
        nil -> throw({"You aren't in voice channel", "Вы не подключены к голосовому каналу"})
      end

      {overrides, channel_name} = case channels do
        %{^channel_id => %{parent_id: ^parent_id, permission_overwrites: overrides, name: channel_name}} -> {overrides, channel_name}
        _ -> throw({"You aren't in managed voice channel", "Вы не подключены к управляемому голосовому каналу"})
      end

      owner_id = case overrides |> Enum.filter(& &1.type == 1) do
        [%{id: owner_id}] -> owner_id
        [_|_] -> throw({"Some problem with permission overwrites: there are too many!", "Слишком много оверрайдов разрешений на канал!"})
        [] -> throw({"Some problem with permission overwrites: there are none", "Отсутствуют оверрайды разрешений на канал"})
      end

      case voice_states |> Enum.find(& &1.channel_id == channel_id and &1.user_id == owner_id) do
        nil -> :ok
        %{} -> throw({"Owner is still connected to channel `#{channel_name}`", "Хозяин канала ещё подключён к `#{channel_name}`"})
      end

      Api.delete_channel_permissions(channel_id, owner_id, "Channel `#{channel_name}` claimed by #{username}") |> IO.inspect
      {:ok} = Api.edit_channel_permissions(channel_id, userid, %{type: "member", allow: DiscordHr.Voice.new_voice_permissions()}, "Channel `#{channel_name}` claimed by #{username}")
      text = case locale do
        "ru" <> _ -> "Канал `#{channel_name}` теперь ваш!"
        _ -> "The channel `#{channel_name}` is yours!"
      end
      DiscordHr.respond_to_interaction(interaction, text)
    catch
      {en, ru} ->
        text = case locale do
          "ru" <> _ -> ru
          _ -> en
        end
        DiscordHr.respond_to_interaction(interaction, text)
    end
  end
end
