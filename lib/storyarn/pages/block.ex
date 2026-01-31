defmodule Storyarn.Pages.Block do
  @moduledoc """
  Schema for blocks.

  A block is a dynamic content field within a page. Blocks can be of different types
  (text, number, select, etc.) and store both configuration and value.

  ## Block Types

  - `text` - Simple text input
  - `rich_text` - Rich text editor (WYSIWYG)
  - `number` - Numeric input
  - `select` - Single select dropdown
  - `multi_select` - Multiple select (tags)

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

  alias Storyarn.Pages.Page

  @block_types ~w(text rich_text number select multi_select)

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}

    belongs_to :page, Page

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
    |> cast(attrs, [:type, :position, :config, :value])
    |> validate_required([:type])
    |> validate_inclusion(:type, @block_types)
    |> validate_config()
  end

  @doc """
  Changeset for updating a block.
  """
  def update_changeset(block, attrs) do
    block
    |> cast(attrs, [:type, :position, :config, :value])
    |> validate_required([:type])
    |> validate_inclusion(:type, @block_types)
    |> validate_config()
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

    case type do
      t when t in ["select", "multi_select"] ->
        validate_select_config(changeset, config)

      _ ->
        changeset
    end
  end

  defp validate_select_config(changeset, config) do
    options = Map.get(config, "options", [])

    if is_list(options) do
      changeset
    else
      add_error(changeset, :config, "options must be a list for select types")
    end
  end

  @doc """
  Builds a default config for a block type.
  """
  def default_config(type) do
    case type do
      "text" -> %{"label" => "", "placeholder" => ""}
      "rich_text" -> %{"label" => ""}
      "number" -> %{"label" => "", "placeholder" => "0"}
      "select" -> %{"label" => "", "placeholder" => "Select...", "options" => []}
      "multi_select" -> %{"label" => "", "placeholder" => "Select...", "options" => []}
      _ -> %{}
    end
  end

  @doc """
  Builds a default value for a block type.
  """
  def default_value(type) do
    case type do
      "text" -> %{"content" => ""}
      "rich_text" -> %{"content" => ""}
      "number" -> %{"content" => nil}
      "select" -> %{"content" => nil}
      "multi_select" -> %{"content" => []}
      _ -> %{}
    end
  end
end
