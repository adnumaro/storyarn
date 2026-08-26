defmodule Storyarn.Localization.Texts.Data.ProjectRecord do
  @moduledoc """
  Consumer-local Project projection backing Texts associations and preloads.

  It carries only the fields required by Texts and performs no persistence I/O.
  Project lifecycle and ordinary writes remain owned by Projects.
  """
  use Ecto.Schema

  alias Storyarn.Localization.Texts.Data.WorkspaceRecord

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
