defmodule Storyarn.AI.Governance.Data.ProjectRecord do
  @moduledoc "Governance-owned projection of project identity and lifecycle for AI authorization."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
