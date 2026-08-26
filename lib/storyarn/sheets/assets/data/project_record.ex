defmodule Storyarn.Sheets.Assets.Data.ProjectRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Sheet asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Sheets.Assets.Data.WorkspaceRecord

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}
    field :auto_version_sheets, :boolean, default: true
    belongs_to :workspace, WorkspaceRecord
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
