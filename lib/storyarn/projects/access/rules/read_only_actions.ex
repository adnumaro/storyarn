defmodule Storyarn.Projects.Access.Rules.ReadOnlyActions do
  @moduledoc """
  The project actions a read-only workspace still allows.

  A workspace is read-only while its owner's account is over its plan's
  limits. Its members keep everything that reads, and everything that brings
  the account back within its limits: viewing, commenting, deleting content
  and the project itself, removing members and pending invitations, and
  reading, downloading and deleting backups. Every other action is refused
  with `:read_only`. The workspace actions that only read its settings stay
  allowed as well.
  """

  @allowed [
    :view,
    :access_workspace_settings,
    :access_workspace_general_settings,
    :comment,
    :delete_content,
    :delete_project,
    :remove_members,
    :read_snapshots,
    :delete_snapshot
  ]

  @spec allowed?(atom()) :: boolean()
  def allowed?(action), do: action in @allowed
end
