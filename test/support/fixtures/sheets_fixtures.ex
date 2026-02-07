defmodule Storyarn.SheetsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  sheets via the `Storyarn.Sheets` context.
  """

  alias Storyarn.Sheets
  alias Storyarn.ProjectsFixtures

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
end
