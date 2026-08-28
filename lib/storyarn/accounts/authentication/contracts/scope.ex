defmodule Storyarn.Accounts.Scope do
  @moduledoc """
  Stable caller contract used throughout the application.

  The scope identifies the authenticated actor without exposing Authentication
  internals. Its module identity is intentionally stable because other bounded
  contexts use it in public types and authorization entry points.
  """

  alias Storyarn.Accounts.User

  @type t :: %__MODULE__{
          user: User.t() | nil
        }

  defstruct user: nil

  @doc "Creates a scope for a user, or returns `nil` when no user is given."
  @spec for_user(User.t() | nil) :: t() | nil
  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
