defmodule Storyarn.Workspaces.Lifecycle.Projections.ProjectRecord do
  @moduledoc """
  Consumer-local SQL projection of project identity for Workspace lifecycle.

  Projects owns project behavior and writes. Lifecycle keeps this minimal view
  so its Workspace entity does not depend on the Projects code model.
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
