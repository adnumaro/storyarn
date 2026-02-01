defmodule Storyarn.Flows.FlowConnection do
  @moduledoc """
  Schema for flow connections.

  A flow connection represents a link between two nodes in the flow graph.
  Connections have source and target pins, and can optionally have labels
  and conditions for conditional branching.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.{Flow, FlowNode}

  @type t :: %__MODULE__{
          id: integer() | nil,
          source_pin: String.t() | nil,
          target_pin: String.t() | nil,
          label: String.t() | nil,
          condition: String.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          source_node_id: integer() | nil,
          source_node: FlowNode.t() | Ecto.Association.NotLoaded.t() | nil,
          target_node_id: integer() | nil,
          target_node: FlowNode.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_connections" do
    field :source_pin, :string
    field :target_pin, :string
    field :label, :string
    field :condition, :string

    belongs_to :flow, Flow
    belongs_to :source_node, FlowNode
    belongs_to :target_node, FlowNode

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new connection.
  """
  def create_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :source_pin,
      :target_pin,
      :label,
      :condition,
      :source_node_id,
      :target_node_id
    ])
    |> validate_required([:source_pin, :target_pin, :source_node_id, :target_node_id])
    |> validate_length(:source_pin, max: 100)
    |> validate_length(:target_pin, max: 100)
    |> validate_length(:label, max: 200)
    |> validate_length(:condition, max: 1000)
    |> validate_not_self_connection()
    |> foreign_key_constraint(:source_node_id)
    |> foreign_key_constraint(:target_node_id)
    |> unique_constraint([:source_node_id, :source_pin, :target_node_id, :target_pin],
      name: :flow_connections_source_node_id_source_pin_target_node_id_targe
    )
  end

  @doc """
  Changeset for updating a connection.
  """
  def update_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:label, :condition])
    |> validate_length(:label, max: 200)
    |> validate_length(:condition, max: 1000)
  end

  defp validate_not_self_connection(changeset) do
    source_id = get_field(changeset, :source_node_id)
    target_id = get_field(changeset, :target_node_id)

    if source_id && target_id && source_id == target_id do
      add_error(changeset, :target_node_id, "cannot connect a node to itself")
    else
      changeset
    end
  end
end
