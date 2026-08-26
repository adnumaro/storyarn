defmodule Storyarn.Sheets.Access.Data.ProjectRecord do
  @moduledoc "Access-owned project identity used for Sheet authorization."

  use Ecto.Schema

  alias Storyarn.Sheets.Access.Data.WorkspaceRecord

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
