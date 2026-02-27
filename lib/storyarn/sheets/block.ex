defmodule Storyarn.Sheets.Block do
  @moduledoc """
  Schema for blocks.

  A block is a dynamic content field within a sheet. Blocks can be of different types
  (text, number, select, etc.) and store both configuration and value.

  ## Block Types

  - `text` - Simple text input
  - `rich_text` - Rich text editor (WYSIWYG)
  - `number` - Numeric input
  - `select` - Single select dropdown
  - `multi_select` - Multiple select (tags)
  - `boolean` - Boolean toggle (two-state or tri-state)
  - `date` - Date picker

  ## Config Structure

  ```elixir
  %{
    "label" => "Field Label",
    "placeholder" => "Enter value...",
    "options" => [                    # Only for select/multi_select
      %{"key" => "opt1", "value" => "Option 1"},
      %{"key" => "opt2", "value" => "Option 2"}
    ]
  }
  ```

  ## Value Structure

  ```elixir
  # For text/rich_text/number:
  %{"content" => "value here"}

  # For select:
  %{"content" => "opt1"}

  # For multi_select:
  %{"content" => ["opt1", "opt2"]}
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Shared.{NameNormalizer, TimeHelpers}
  alias Storyarn.Sheets.Sheet

  @block_types ~w(text rich_text number select multi_select date boolean reference table)

  @default_configs %{
    "text" => %{"label" => "Label", "placeholder" => ""},
    "rich_text" => %{"label" => "Label"},
    "number" => %{
      "label" => "Label",
      "placeholder" => "0",
      "min" => nil,
      "max" => nil,
      "step" => nil
    },
    "select" => %{"label" => "Label", "placeholder" => "Select...", "options" => []},
    "multi_select" => %{"label" => "Label", "placeholder" => "Select...", "options" => []},
    "date" => %{"label" => "Label"},
    "boolean" => %{"label" => "Label", "mode" => "two_state"},
    "reference" => %{"label" => "Label", "allowed_types" => ["sheet", "flow"]},
    "table" => %{"label" => "Label", "collapsed" => false}
  }

  @default_values %{
    "text" => %{"content" => ""},
    "rich_text" => %{"content" => ""},
    "number" => %{"content" => nil},
    "select" => %{"content" => nil},
    "multi_select" => %{"content" => []},
    "date" => %{"content" => nil},
    "boolean" => %{"content" => nil},
    "reference" => %{"target_type" => nil, "target_id" => nil},
    "table" => %{}
  }

  # Block types that cannot be variables (no meaningful value to expose)
  @non_variable_types ~w(reference)

  @scopes ~w(self children)

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          position: integer() | nil,
          config: map() | nil,
          value: map() | nil,
          is_constant: boolean(),
          variable_name: String.t() | nil,
          scope: String.t(),
          inherited_from_block_id: integer() | nil,
          detached: boolean(),
          required: boolean(),
          column_group_id: Ecto.UUID.t() | nil,
          column_index: integer(),
          sheet_id: integer() | nil,
          sheet: Sheet.t() | Ecto.Association.NotLoaded.t() | nil,
          inherited_from_block: t() | Ecto.Association.NotLoaded.t() | nil,
          inherited_instances: [t()] | Ecto.Association.NotLoaded.t(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :scope, :string, default: "self"
    field :detached, :boolean, default: false
    field :required, :boolean, default: false
    field :column_group_id, Ecto.UUID
    field :column_index, :integer, default: 0
    field :deleted_at, :utc_datetime

    belongs_to :sheet, Sheet
    belongs_to :inherited_from_block, __MODULE__
    has_many :inherited_instances, __MODULE__, foreign_key: :inherited_from_block_id
    has_many :table_columns, Storyarn.Sheets.TableColumn, foreign_key: :block_id
    has_many :table_rows, Storyarn.Sheets.TableRow, foreign_key: :block_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid block types.
  """
  def types, do: @block_types

  @doc """
  Changeset for creating a new block.
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

  @doc """
  Changeset for updating a block.
  """
  def update_changeset(block, attrs) do
    block
    |> cast(attrs, [
      :type,
      :position,
      :config,
      :value,
      :is_constant,
      :variable_name,
      :scope,
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
  end

  @doc """
  Changeset for updating only the value of a block.
  """
  def value_changeset(block, attrs) do
    block
    |> cast(attrs, [:value])
  end

  @doc """
  Changeset for updating only the config of a block.
  """
  def config_changeset(block, attrs) do
    block
    |> cast(attrs, [:config])
    |> validate_config()
    |> maybe_generate_variable_name()
  end

  @doc """
  Changeset for updating variable settings.
  """
  def variable_changeset(block, attrs) do
    block
    |> cast(attrs, [:is_constant, :variable_name])
  end

  @doc """
  Changeset for reordering blocks.
  """
  def position_changeset(block, attrs) do
    block
    |> cast(attrs, [:position])
  end

  # Validates config based on block type
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

  @doc """
  Builds a default config for a block type.
  """
  def default_config(type), do: Map.get(@default_configs, type, %{})

  @doc """
  Builds a default value for a block type.
  """
  def default_value(type), do: Map.get(@default_values, type, %{})

  @doc """
  Changeset for soft deleting a block.
  """
  def delete_changeset(block) do
    block
    |> change(%{deleted_at: TimeHelpers.now()})
  end

  @doc """
  Changeset for restoring a soft-deleted block.
  """
  def restore_changeset(block) do
    block
    |> change(%{deleted_at: nil})
  end

  @doc """
  Returns true if the block is soft-deleted.
  """
  def deleted?(%__MODULE__{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  @doc """
  Returns true if the block type can be a variable.
  Reference blocks cannot be variables as they have no meaningful value.
  """
  def can_be_variable?(type), do: type not in @non_variable_types

  @doc """
  Returns true if the block is exposed as a variable.
  A block is a variable if it's not marked as constant and its type supports variables.
  """
  def variable?(%__MODULE__{type: type, is_constant: is_constant}) do
    can_be_variable?(type) and not is_constant
  end

  @doc """
  Returns the list of valid scopes.
  """
  def scopes, do: @scopes

  @doc """
  Returns true if the block is an active inherited instance (not detached).
  """
  def inherited?(%__MODULE__{inherited_from_block_id: nil}), do: false
  def inherited?(%__MODULE__{detached: true}), do: false
  def inherited?(%__MODULE__{}), do: true

  # Generates variable_name from label in config.
  # Only generates if variable_name is not yet set (new block or first label).
  # The CRUD layer handles conditional regeneration for existing blocks.
  defp maybe_generate_variable_name(changeset) do
    type = get_field(changeset, :type)

    cond do
      not can_be_variable?(type) ->
        put_change(changeset, :variable_name, nil)

      get_field(changeset, :variable_name) != nil ->
        changeset

      true ->
        label = (get_field(changeset, :config) || %{}) |> Map.get("label")

        if label,
          do: put_change(changeset, :variable_name, NameNormalizer.variablify(label)),
          else: changeset
    end
  end
end
