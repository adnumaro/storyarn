defmodule Storyarn.Localization.Persistence.ProjectRecord do
  @moduledoc false

  use Ecto.Schema

  alias Storyarn.Localization.Persistence.WorkspaceRecord

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
