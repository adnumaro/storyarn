defmodule Storyarn.AI.Integrations.Projections.WorkspaceRecord do
  @moduledoc """
  Minimal read projection of a workspace used by Integrations.

  Workspaces owns the table. Integrations reads identity and display fields for
  assignment and preference views and never mutates a workspace through this
  schema.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
