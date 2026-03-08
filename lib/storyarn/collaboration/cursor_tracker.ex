defmodule Storyarn.Collaboration.CursorTracker do
  @moduledoc """
  PubSub-based cursor position broadcasting.

  Uses `broadcast_from/4` so the sender does not receive their own cursor updates.
  Accepts editor_scope tuples like `{:flow, id}`, `{:sheet, id}`, etc.
  """

  alias Phoenix.PubSub
  alias Storyarn.Collaboration.Colors

  @type editor_scope :: {atom(), integer()}

  @type cursor_position :: %{
          user_id: integer(),
          user_email: String.t(),
          user_color: String.t(),
          x: float(),
          y: float()
        }

  @doc """
  Broadcasts a cursor position update to all other users in an editor.
  Uses `broadcast_from` to exclude the sender.
  """
  @spec broadcast_cursor(editor_scope(), map(), float(), float()) :: :ok
  def broadcast_cursor(scope, user, x, y) do
    PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      cursor_topic(scope),
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
  Broadcasts that a user's cursor has left the editor.
  """
  @spec broadcast_cursor_leave(editor_scope(), integer()) :: :ok
  def broadcast_cursor_leave(scope, user_id) do
    PubSub.broadcast_from(Storyarn.PubSub, self(), cursor_topic(scope), {:cursor_leave, user_id})
  end

  @doc """
  Subscribes to cursor updates for an editor.
  """
  @spec subscribe(editor_scope()) :: :ok | {:error, term()}
  def subscribe(scope) do
    PubSub.subscribe(Storyarn.PubSub, cursor_topic(scope))
  end

  @doc """
  Unsubscribes from cursor updates for an editor.
  """
  @spec unsubscribe(editor_scope()) :: :ok
  def unsubscribe(scope) do
    PubSub.unsubscribe(Storyarn.PubSub, cursor_topic(scope))
  end

  @doc """
  Returns the topic for cursor updates.
  """
  @spec cursor_topic({atom(), integer()}) :: String.t()
  def cursor_topic({type, id}), do: "#{type}:#{id}:cursors"
end
