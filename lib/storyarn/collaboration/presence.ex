defmodule Storyarn.Collaboration.Presence do
  @moduledoc """
  Phoenix.Presence for real-time user tracking across all editors.

  Uses the proxy topic pattern: when presence changes happen, structured
  `{:join, data}` / `{:leave, data}` messages are broadcast on a
  `"proxy:{topic}"` channel. LiveViews subscribe to the proxy topic for
  efficient updates.
  """

  use Phoenix.Presence,
    otp_app: :storyarn,
    pubsub_server: Storyarn.PubSub

  alias Storyarn.Collaboration.Colors

  @type presence_meta :: %{
          user_id: integer(),
          email: String.t(),
          display_name: String.t() | nil,
          avatar_url: String.t() | nil,
          color: String.t(),
          joined_at: DateTime.t()
        }

  # =============================================================================
  # Phoenix.Presence Callbacks
  # =============================================================================

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def fetch(_topic, presences) do
    for {key, %{metas: metas}} <- presences, into: %{} do
      meta = List.first(metas)

      user_data =
        if meta do
          %{
            id: meta.user_id,
            email: meta.email,
            display_name: meta.display_name,
            avatar_url: meta[:avatar_url],
            color: meta.color
          }
        else
          %{}
        end

      {key, %{metas: metas, id: key, user: user_data}}
    end
  end

  @impl true
  def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
    for {user_id, presence} <- joins do
      user_data = %{
        id: user_id,
        user: presence.user,
        metas: Map.get(presences, user_id, %{metas: []})
      }

      Phoenix.PubSub.local_broadcast(
        Storyarn.PubSub,
        "proxy:#{topic}",
        {__MODULE__, {:join, user_data}}
      )
    end

    for {user_id, presence} <- leaves do
      metas =
        case Map.fetch(presences, user_id) do
          {:ok, data} -> data
          :error -> %{metas: []}
        end

      user_data = %{
        id: user_id,
        user: presence.user,
        metas: metas
      }

      Phoenix.PubSub.local_broadcast(
        Storyarn.PubSub,
        "proxy:#{topic}",
        {__MODULE__, {:leave, user_data}}
      )
    end

    {:ok, state}
  end

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Tracks a user's presence on a topic.
  """
  @spec track_user(pid(), String.t(), map(), map()) ::
          {:ok, binary()} | {:error, term()}
  def track_user(pid, topic, user, extra_meta \\ %{}) do
    meta =
      Map.merge(
        %{
          user_id: user.id,
          email: user.email,
          display_name: Map.get(user, :display_name),
          avatar_url: Map.get(user, :avatar_url),
          color: Colors.for_user(user.id),
          joined_at: DateTime.utc_now()
        },
        extra_meta
      )

    track(pid, topic, user.id, meta)
  end

  @doc """
  Returns a list of users currently on a topic, formatted for display.
  """
  @spec list_users(String.t()) :: [presence_meta()]
  def list_users(topic) do
    topic
    |> list()
    |> Enum.map(fn {_user_id, data} ->
      data.metas |> List.first()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.joined_at, {:asc, DateTime})
  end

  @doc """
  Returns the presence topic for an editor scope.
  """
  @spec topic({atom(), integer()}) :: String.t()
  def topic({type, id}), do: "#{type}:#{id}:presence"
end
