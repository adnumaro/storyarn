defmodule Storyarn.Projects.Comments.Thread do
  @moduledoc "A durable, project-owned discussion anchored to one source identity."
  use Ecto.Schema

  schema "comment_threads" do
    field :project_id, :integer
    field :author_id, :integer
    field :source_type, :string
    field :source_id, :integer
    field :flow_node_id, :integer
    field :flow_canvas_id, :integer
    field :scene_canvas_id, :integer
    field :sheet_canvas_id, :integer
    field :position_x, :float
    field :position_y, :float
    field :container_id, :integer
    field :source_inserted_at, :utc_datetime
    field :source_label, :string
    field :status, :string, default: "open"
    field :revision, :integer, default: 1
    field :message_count, :integer, default: 0
    field :resolved_at, :utc_datetime
    field :resolved_by_id, :integer
    field :last_activity_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
