defmodule Storyarn.Workspaces.Memberships.Rules.ReadOnlyActions do
  @moduledoc """
  The workspace actions a read-only workspace still allows.

  A workspace is read-only while its owner's account is over its plan's
  limits. Its members can still read it, and its owner can still bring the
  account back within its limits by deleting the workspace, removing members
  and revoking pending invitations. Every other action is refused with
  `:read_only`.
  """

  @allowed [
    :view,
    :view_workspace_usage,
    :access_workspace_settings,
    :access_workspace_general_settings,
    :remove_members,
    :delete_workspace
  ]

  @spec allowed?(atom()) :: boolean()
  def allowed?(action), do: action in @allowed
end
