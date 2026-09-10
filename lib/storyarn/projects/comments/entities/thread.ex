defmodule Storyarn.Projects.Comments.Thread do
  @moduledoc "A durable discussion owned by an editor surface, with an optional contextual reference."
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
    field :context_type, :string
    field :context_id, :string
    field :context_label, :string
    field :context_inserted_at, :utc_datetime
    field :context_offset_x, :float
    field :context_offset_y, :float
    field :context_sheet_block_id, :integer
    field :context_sheet_column_group_id, Ecto.UUID
    field :context_scene_pin_id, :integer
    field :context_scene_zone_id, :integer
    field :context_scene_connection_id, :integer
    field :context_scene_annotation_id, :integer
    field :status, :string, default: "open"
    field :revision, :integer, default: 1
    field :message_count, :integer, default: 0
    field :resolved_at, :utc_datetime
    field :resolved_by_id, :integer
    field :last_activity_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
