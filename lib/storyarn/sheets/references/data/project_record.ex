defmodule Storyarn.Sheets.References.Data.ProjectRecord do
  @moduledoc """
  References-local projection of project identity and active state.

  Reference writers lock this record before foreign targets to keep project
  trash transitions mutually exclusive with new Sheet references. It owns no
  Project lifecycle behavior.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}
    field :auto_version_sheets, :boolean, default: true
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
