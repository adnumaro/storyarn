defmodule Storyarn.Projects.Persistence.BlockRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Persistence.BlockGalleryImageRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.Persistence.TableColumnRecord
  alias Storyarn.Projects.Persistence.TableRowRecord

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :word_count, :integer, default: 0
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :scope, :string, default: "self"
    field :required, :boolean, default: false
    field :detached, :boolean, default: false
    field :column_group_id, Ecto.UUID
    field :column_index, :integer, default: 0
    belongs_to :inherited_from_block, __MODULE__
    field :deleted_at, :utc_datetime

    belongs_to :sheet, SheetRecord
    has_many :table_columns, TableColumnRecord, foreign_key: :block_id
    has_many :table_rows, TableRowRecord, foreign_key: :block_id
    has_many :gallery_images, BlockGalleryImageRecord, foreign_key: :block_id

    timestamps(type: :utc_datetime)
  end

  @block_types ~w(text rich_text number select multi_select date boolean reference table gallery)
  @scopes ~w(self children)

  @doc "Changeset for updating only the value of a block."
  def value_changeset(block, attrs) do
    cast(block, attrs, [:value])
  end

  @doc "The closed catalog of block types a snapshot may carry."
  def types, do: @block_types

  @doc """
  Validation-only changeset mirroring the Sheet tool's block create rules.

  Variable-name generation is omitted on purpose: it only rewrites a field and
  never adds errors, so validity is identical without it.
  """
  def create_changeset(block, attrs) do
    block
    |> cast(attrs, [
      :type,
      :position,
      :config,
      :value,
      :is_constant,
      :variable_name,
      :scope,
      :inherited_from_block_id,
      :detached,
      :required,
      :column_group_id,
      :column_index
    ])
    |> validate_required([:type])
    |> validate_inclusion(:type, @block_types)
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:column_index, 0..2)
    |> validate_config()
    |> maybe_generate_variable_name()
    |> foreign_key_constraint(:inherited_from_block_id)
  end

  @non_variable_types ~w(reference gallery)

  # Only generates if variable_name is not yet set (new block or first label);
  # mirror of the Sheet tool's block changeset.
  defp maybe_generate_variable_name(changeset) do
    type = get_field(changeset, :type)

    cond do
      type in @non_variable_types ->
        put_change(changeset, :variable_name, nil)

      get_field(changeset, :variable_name) != nil ->
        changeset

      true ->
        label = Map.get(get_field(changeset, :config) || %{}, "label")

        if label,
          do: put_change(changeset, :variable_name, Storyarn.Projects.SheetNaming.variablify(label)),
          else: changeset
    end
  end

  defp validate_config(changeset) do
    type = get_field(changeset, :type)
    config = get_field(changeset, :config) || %{}

    changeset
    |> validate_label(type, config)
    |> validate_select_options(type, config)
  end

  defp validate_label(changeset, _type, config) do
    label = Map.get(config, "label")

    if is_nil(label) or label == "" do
      add_error(changeset, :config, "label is required")
    else
      changeset
    end
  end

  defp validate_select_options(changeset, type, config) when type in ["select", "multi_select"] do
    options = Map.get(config, "options", [])

    if is_list(options) do
      changeset
    else
      add_error(changeset, :config, "options must be a list for select types")
    end
  end

  defp validate_select_options(changeset, _type, _config), do: changeset
end
