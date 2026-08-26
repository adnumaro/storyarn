defmodule Storyarn.Sheets.Editor.Data.WorkspaceRecord do
  @moduledoc """
  Minimal Workspace identity embedded in the Sheet editor's Project projection.

  It is a passive read model over the shared table and owns no Workspace rules.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
