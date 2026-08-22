defmodule Storyarn.Assets.Persistence.EntityTrashRefRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flows_entity_trash_refs" do
    field :source_type, :string
    field :source_id, :integer
    field :source_field, :string

    field :target_sheet_id, :integer
    field :target_asset_id, :integer
    field :target_flow_id, :integer
    field :target_flow_node_id, :integer
    field :target_sheet_avatar_id, :integer

    field :inserted_at, :utc_datetime
  end
end
