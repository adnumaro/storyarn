defmodule Storyarn.Flows.EntityTrashRef do
  @moduledoc """
  Schema for `flows_entity_trash_refs`.

  One row represents a single source-to-target reference that was swept
  when the target entity was soft-deleted. On target restore, the ref is
  re-applied to the source field and the row is deleted. On target
  hard-delete, the row cascades away via the target FK.

  `source_type` is constrained (changeset) to `flow_node` — this table
  lives in the flows domain, so sources are always flow-domain entities.
  `target_*` columns are one-of: exactly one is non-null (DB + changeset).

  `source_field` is a free-form path string:

    * column field on the source:        `"referenced_flow_id"`
    * JSONB field on `flow_nodes.data`:  `"data.speaker_sheet_id"`
    * JSONB nested path:                 `"legacy.path[0].asset_id"`

  The `Storyarn.Flows.EntityTrashRefs` module owns the generic sweep/restore
  API and interprets `source_field` paths.

  The `flow_sequence` source_type and `target_flow_sequence_id` target
  were removed in Phase 1 of the flow relational refactor. The column
  `target_flow_sequence_id` still exists in the DB (dead weight) until
  F7 drops the entire `flows_entity_trash_refs` table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Shared.TimeHelpers

  @source_types ~w(flow_node)

  @target_fields ~w(
    target_sheet_id
    target_asset_id
    target_flow_id
    target_flow_node_id
    target_sheet_avatar_id
  )a

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          source_field: String.t() | nil,
          target_sheet_id: integer() | nil,
          target_asset_id: integer() | nil,
          target_flow_id: integer() | nil,
          target_flow_node_id: integer() | nil,
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

  @doc "Returns the list of valid source_type values."
  @spec source_types() :: [String.t()]
  def source_types, do: @source_types

  @doc "Returns the target column names (as atoms)."
  @spec target_fields() :: [atom()]
  def target_fields, do: @target_fields

  @doc """
  Changeset for inserting a new trash ref. Exactly one `target_*` field
  must be set.
  """
  def create_changeset(trash_ref \\ %__MODULE__{}, attrs) do
    trash_ref
    |> cast(attrs, [:source_type, :source_id, :source_field, :inserted_at | @target_fields])
    |> validate_required([:source_type, :source_id, :source_field])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_exactly_one_target()
    |> put_default_inserted_at()
    |> foreign_key_constraint(:target_sheet_id)
    |> foreign_key_constraint(:target_asset_id)
    |> foreign_key_constraint(:target_flow_id)
    |> foreign_key_constraint(:target_flow_node_id)
    |> foreign_key_constraint(:target_sheet_avatar_id)
    |> check_constraint(:source_type, name: :source_type_valid)
    |> check_constraint(:target_sheet_id, name: :exactly_one_target)
  end

  defp validate_exactly_one_target(changeset) do
    set_count = Enum.count(@target_fields, &(get_field(changeset, &1) != nil))

    case set_count do
      1 ->
        changeset

      n ->
        add_error(
          changeset,
          :target_sheet_id,
          "exactly one target_* field must be non-null (got #{n})"
        )
    end
  end

  defp put_default_inserted_at(changeset) do
    case get_field(changeset, :inserted_at) do
      nil -> put_change(changeset, :inserted_at, TimeHelpers.now())
      _ -> changeset
    end
  end
end
