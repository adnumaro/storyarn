defmodule Storyarn.Sheets.References.Data.SceneRecord do
  @moduledoc """
  References-local projection of Scene identity, project ownership, and trash.

  It supports Scene backlink labels and reference validation without coupling
  Sheets to the Scene aggregate or editor implementation.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :name, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
