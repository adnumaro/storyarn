defmodule Storyarn.Localization.Access.Data.ProjectRecord do
  @moduledoc """
  Access-owned read projection over active project identity.
  """

  use Ecto.Schema

  alias Storyarn.Localization.Access.Data.WorkspaceRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          workspace_id: integer() | nil,
          workspace: WorkspaceRecord.t() | Ecto.Association.NotLoaded.t() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :deleted_at, :utc_datetime

    belongs_to :workspace, WorkspaceRecord

    timestamps(type: :utc_datetime)
  end
end
