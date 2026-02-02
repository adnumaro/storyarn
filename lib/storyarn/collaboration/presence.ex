defmodule Storyarn.Collaboration.Presence do
  @moduledoc false

  use Phoenix.Presence,
    otp_app: :storyarn,
    pubsub_server: Storyarn.PubSub

  alias Storyarn.Collaboration.Colors

  @type presence_meta :: %{
          user_id: integer(),
          email: String.t(),
          display_name: String.t() | nil,
          color: String.t(),
          joined_at: DateTime.t()
        }

  @doc """
  Tracks a user's presence in a flow.
  """
  @spec track_user(pid(), String.t(), Storyarn.Accounts.User.t()) ::
          {:ok, binary()} | {:error, term()}
  def track_user(pid, flow_topic, user) do
    track(pid, flow_topic, user.id, %{
      user_id: user.id,
      email: user.email,
      display_name: user.display_name,
      color: Colors.for_user(user.id),
      joined_at: DateTime.utc_now()
    })
  end

  @doc """
  Returns a list of users currently in a flow, formatted for display.
  """
  @spec list_users(String.t()) :: [presence_meta()]
  def list_users(flow_topic) do
    flow_topic
    |> list()
    |> Enum.map(fn {_user_id, data} ->
      # Get the first (most recent) presence for this user
      data.metas |> List.first()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.joined_at, {:asc, DateTime})
  end

  @doc """
  Returns the topic for a flow's presence channel.
  """
  @spec flow_topic(integer()) :: String.t()
  def flow_topic(flow_id) do
    "flow:#{flow_id}:presence"
  end
end
