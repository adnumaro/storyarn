defmodule Storyarn.Flows.VariableReference do
  @moduledoc """
  Schema for variable references.

  Tracks which flow nodes read or write which variables (blocks).
  Used to show variable usage in the page editor and detect stale references.

  ## Kinds

  - `"read"` — The node reads this variable (e.g., condition node checking a value)
  - `"write"` — The node writes this variable (e.g., instruction node setting a value)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Pages.Block

  @type t :: %__MODULE__{
          id: integer() | nil,
          flow_node_id: integer() | nil,
          block_id: integer() | nil,
          kind: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "variable_references" do
    belongs_to :flow_node, FlowNode
    belongs_to :block, Block
    field :kind, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a variable reference.
  """
  def changeset(ref, attrs) do
    ref
    |> cast(attrs, [:flow_node_id, :block_id, :kind])
    |> validate_required([:flow_node_id, :block_id, :kind])
    |> validate_inclusion(:kind, ["read", "write"])
    |> unique_constraint([:flow_node_id, :block_id, :kind])
  end
end
