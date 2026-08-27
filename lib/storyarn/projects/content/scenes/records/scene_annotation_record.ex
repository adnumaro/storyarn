defmodule Storyarn.Projects.Persistence.SceneAnnotationRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Storyarn.Projects.SceneChangesetHelpers

  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.SceneRecord

  @valid_font_sizes ~w(sm md lg)

  schema "scene_annotations" do
    field :text, :string
    field :position_x, :float
    field :position_y, :float
    field :font_size, :string, default: "md"
    field :color, :string
    field :position, :integer, default: 0
    field :locked, :boolean, default: false

    belongs_to :scene, SceneRecord
    belongs_to :layer, SceneLayerRecord

    timestamps(type: :utc_datetime)
  end

  def create_changeset(annotation, attrs), do: shared_changeset(annotation, attrs)

  defp shared_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:text, :position_x, :position_y, :font_size, :color, :layer_id, :position, :locked])
    |> validate_required([:text, :position_x, :position_y])
    |> validate_length(:text, min: 1, max: 500)
    |> validate_inclusion(:font_size, @valid_font_sizes)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> foreign_key_constraint(:layer_id)
  end
end
