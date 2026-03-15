defmodule Storyarn.References.VariableReference do
  @moduledoc """
  Canonical schema for variable references.

  Tracks reads and writes from flow nodes and scene elements to sheet blocks.

  ## Source Types
  - `"flow_node"`
  - `"scene_pin"`
  - `"scene_zone"`
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Sheets.Block

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          flow_node_id: integer() | nil,
          block_id: integer() | nil,
          kind: String.t() | nil,
          source_sheet: String.t() | nil,
          source_variable: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @source_types ~w(flow_node scene_pin scene_zone)

  schema "variable_references" do
    field :source_type, :string, default: "flow_node"
    field :source_id, :integer
    belongs_to :flow_node, FlowNode
    belongs_to :block, Block
    field :kind, :string
    field :source_sheet, :string
    field :source_variable, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ref, attrs) do
    ref
    |> cast(attrs, [
      :source_type,
      :source_id,
      :flow_node_id,
      :block_id,
      :kind,
      :source_sheet,
      :source_variable
    ])
    |> validate_required([
      :source_type,
      :source_id,
      :block_id,
      :kind,
      :source_sheet,
      :source_variable
    ])
    |> validate_inclusion(:kind, ["read", "write"])
    |> validate_inclusion(:source_type, @source_types)
    |> unique_constraint([:source_type, :source_id, :block_id, :kind, :source_variable],
      name: :variable_references_source_block_kind_var
    )
  end
end
