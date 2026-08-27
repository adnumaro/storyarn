defmodule Storyarn.Localization.Languages.Projections.ProjectRecord do
  @moduledoc """
  Languages-owned projection over Project identity and its workspace source locale.
  """

  use Ecto.Schema

  alias Storyarn.Localization.Languages.Projections.WorkspaceRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          deleted_at: DateTime.t() | nil,
          workspace_id: integer() | nil,
          workspace: WorkspaceRecord.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :deleted_at, :utc_datetime

    belongs_to :workspace, WorkspaceRecord

    timestamps(type: :utc_datetime)
  end
end
