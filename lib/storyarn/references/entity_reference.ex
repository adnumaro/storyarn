defmodule Storyarn.References.EntityReference do
  @moduledoc """
  Canonical schema for tracking entity references across Storyarn content.

  ## Source Types
  - `"block"`
  - `"flow_node"`
  - `"screenplay_element"`
  - `"scene_pin"`
  - `"scene_zone"`

  ## Target Types
  - `"sheet"`
  - `"flow"`
  - `"scene"`
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @source_types ~w(block flow_node screenplay_element scene_pin scene_zone)
  @target_types ~w(sheet flow scene)

  schema "entity_references" do
    field :source_type, :string
    field :source_id, :id
    field :target_type, :string
    field :target_id, :id
    field :context, :string

    timestamps()
  end

  @doc false
  def changeset(entity_reference, attrs) do
    entity_reference
    |> cast(attrs, [:source_type, :source_id, :target_type, :target_id, :context])
    |> validate_required([:source_type, :source_id, :target_type, :target_id])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:target_type, @target_types)
    |> unique_constraint([:source_type, :source_id, :target_type, :target_id, :context],
      name: :entity_references_unique
    )
  end
end
