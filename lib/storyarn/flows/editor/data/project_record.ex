defmodule Storyarn.Flows.Editor.Data.ProjectRecord do
  @moduledoc """
  Consumer-local Project projection used to protect Flow editor writes.

  Projects owns the shared table. Editor intentionally duplicates the minimal
  project state required by its transactions and capacity checks.
  """

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
