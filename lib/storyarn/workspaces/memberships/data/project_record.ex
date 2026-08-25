defmodule Storyarn.Workspaces.Memberships.Data.ProjectRecord do
  @moduledoc """
  Consumer-local SQL projection of project identity for Workspace membership.

  Projects owns the project lifecycle. Memberships needs only these fields to
  derive Workspace access through project membership.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
