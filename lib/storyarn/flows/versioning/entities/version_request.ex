defmodule Storyarn.Flows.Versioning.VersionRequest do
  @moduledoc "A durable, immutable capture awaiting publication in Flow history."
  use Ecto.Schema

  schema "flow_version_requests" do
    field :flow_id, :id
    field :project_id, :id
    field :created_by_id, :id
    field :version_id, :id
    field :snapshot, :map
    field :title, :string
    field :description, :string
    field :is_auto, :boolean, default: false
    field :status, :string, default: "pending"
    timestamps(type: :utc_datetime)
  end
end
