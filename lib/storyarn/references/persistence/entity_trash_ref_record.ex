defmodule Storyarn.References.Persistence.EntityTrashRefRecord do
  @moduledoc """
  References-owned read model for pending Flow entity trash references.

  These rows keep JSON references restorable while their targets are in trash.
  Avatar integrity only needs their identity and avatar target column.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          source_field: String.t() | nil,
          target_sheet_avatar_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

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
