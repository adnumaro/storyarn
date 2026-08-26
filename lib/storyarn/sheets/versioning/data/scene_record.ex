defmodule Storyarn.Sheets.Versioning.Data.SceneRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Sheet versions without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :name, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
