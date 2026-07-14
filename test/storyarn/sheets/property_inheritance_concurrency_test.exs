defmodule Storyarn.Sheets.PropertyInheritanceConcurrencyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets

  test "inherited propagation and direct creation allocate distinct child positions" do
    project = project_fixture()
    parent = sheet_fixture(project, %{name: "Parent"})
    child = child_sheet_fixture(project, parent, %{name: "Child"})

    operations = [
      fn ->
        Sheets.create_block(parent, %{
          type: "text",
          scope: "children",
          config: %{"label" => "Inherited"},
          value: %{"content" => ""}
        })
      end,
      fn ->
        Sheets.create_block(child, %{
          type: "text",
          config: %{"label" => "Local"},
          value: %{"content" => ""}
        })
      end
    ]

    results =
      operations
      |> Task.async_stream(& &1.(), max_concurrency: 2, ordered: false, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _block}, &1))

    child_blocks = Sheets.list_blocks(child.id)
    assert length(child_blocks) == 2
    assert child_blocks |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 2
  end

  test "concurrent moves share project position allocation" do
    project = project_fixture()
    target = sheet_fixture(project, %{name: "Target"})
    first = sheet_fixture(project, %{name: "First"})
    second = sheet_fixture(project, %{name: "Second"})

    moved =
      [first, second]
      |> Task.async_stream(&Sheets.move_sheet(&1, target.id),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {:ok, sheet}} -> sheet end)

    assert moved |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 2
  end
end
