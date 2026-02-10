defmodule Storyarn.SheetsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  sheets via the `Storyarn.Sheets` context.
  """

  alias Storyarn.ProjectsFixtures
  alias Storyarn.Sheets

  def unique_sheet_name, do: "Sheet #{System.unique_integer([:positive])}"

  def valid_sheet_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_sheet_name()
    })
  end

  @doc """
  Creates a sheet.
  """
  def sheet_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, sheet} =
      attrs
      |> valid_sheet_attributes()
      |> then(&Sheets.create_sheet(project, &1))

    sheet
  end

  def unique_block_label, do: "Field #{System.unique_integer([:positive])}"

  @doc """
  Creates a block within a sheet.
  """
  def block_fixture(sheet, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        type: "text",
        config: %{"label" => unique_block_label(), "placeholder" => "Enter text..."},
        value: %{"content" => ""}
      })

    {:ok, block} = Sheets.create_block(sheet, attrs)
    block
  end

  @doc """
  Creates a child sheet under the given parent.
  """
  def child_sheet_fixture(project, parent, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:parent_id, parent.id)
      |> valid_sheet_attributes()

    {:ok, sheet} = Sheets.create_sheet(project, attrs)
    sheet
  end

  @doc """
  Creates a block with `scope: "children"` (inheritable to descendants).
  """
  def inheritable_block_fixture(sheet, attrs \\ []) do
    attrs = Enum.into(attrs, %{})
    label = attrs[:label] || unique_block_label()
    type = attrs[:type] || "text"

    block_attrs = %{
      type: type,
      scope: "children",
      config: %{"label" => label, "placeholder" => ""},
      value: Storyarn.Sheets.Block.default_value(type)
    }

    block_attrs =
      if Map.has_key?(attrs, :required), do: Map.put(block_attrs, :required, attrs[:required]), else: block_attrs

    {:ok, block} = Sheets.create_block(sheet, block_attrs)
    block
  end
end
