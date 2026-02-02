defmodule Storyarn.Collaboration.CursorTracker do
  @moduledoc false

  alias Phoenix.PubSub
  alias Storyarn.Collaboration.Colors

  @type cursor_position :: %{
          user_id: integer(),
          user_email: String.t(),
          user_color: String.t(),
          x: float(),
          y: float()
        }

  @doc """
  Broadcasts a cursor position update to all users in a flow.
  """
  @spec broadcast_cursor(integer(), Storyarn.Accounts.User.t(), float(), float()) :: :ok
  def broadcast_cursor(flow_id, user, x, y) do
    PubSub.broadcast(
      Storyarn.PubSub,
      cursor_topic(flow_id),
      {:cursor_update,
       %{
         user_id: user.id,
         user_email: user.email,
         user_color: Colors.for_user(user.id),
         x: x,
         y: y
       }}
    )
  end

  @doc """
  Broadcasts that a user's cursor has left the flow.
  """
  @spec broadcast_cursor_leave(integer(), integer()) :: :ok
  def broadcast_cursor_leave(flow_id, user_id) do
    PubSub.broadcast(Storyarn.PubSub, cursor_topic(flow_id), {:cursor_leave, user_id})
  end

  @doc """
  Subscribes to cursor updates for a flow.
  """
  @spec subscribe(integer()) :: :ok | {:error, term()}
  def subscribe(flow_id) do
    PubSub.subscribe(Storyarn.PubSub, cursor_topic(flow_id))
  end

  @doc """
  Unsubscribes from cursor updates for a flow.
  """
  @spec unsubscribe(integer()) :: :ok
  def unsubscribe(flow_id) do
    PubSub.unsubscribe(Storyarn.PubSub, cursor_topic(flow_id))
  end

  @doc """
  Returns the topic for a flow's cursor channel.
  """
  @spec cursor_topic(integer()) :: String.t()
  def cursor_topic(flow_id) do
    "flow:#{flow_id}:cursors"
  end
end
