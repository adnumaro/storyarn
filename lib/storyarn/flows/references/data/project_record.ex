defmodule Storyarn.Flows.References.Data.ProjectRecord do
  @moduledoc "Consumer-owned projection of project identity used to scope Flow references."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}
    field :auto_version_flows, :boolean, default: true
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
