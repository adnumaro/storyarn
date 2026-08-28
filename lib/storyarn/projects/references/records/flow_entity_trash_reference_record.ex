defmodule Storyarn.Projects.Persistence.FlowEntityTrashReferenceRecord do
  @moduledoc """
  Project-owned persistence record for Flow references suspended while an
  exact project replacement moves its current graph to recoverable trash.

  The SQL table is shared with the Flow context, but Project owns this record
  and its reconstitution semantics independently.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          source_field: String.t() | nil,
          target_sheet_id: integer() | nil,
          target_asset_id: integer() | nil,
          target_flow_id: integer() | nil,
          target_flow_node_id: integer() | nil,
          target_flow_sequence_id: integer() | nil,
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
    field :target_flow_sequence_id, :integer
    field :target_sheet_avatar_id, :integer

    field :inserted_at, :utc_datetime
  end
end
