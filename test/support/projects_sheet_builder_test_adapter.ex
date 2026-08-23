defmodule StoryarnTest.ProjectsSheetBuilderTestAdapter do
  @moduledoc false

  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.SheetBuilder

  def build_snapshot(sheet), do: sheet |> sheet_record!() |> SheetBuilder.build_snapshot()
  def build_capture_snapshot(sheet), do: sheet |> sheet_record!() |> SheetBuilder.build_capture_snapshot()

  defdelegate validate_portable_snapshot(snapshot), to: SheetBuilder
  defdelegate instantiate_snapshot(project_id, snapshot, opts \\ []), to: SheetBuilder
  defdelegate diff_snapshots(old_snapshot, new_snapshot), to: SheetBuilder
  defdelegate scan_references(snapshot), to: SheetBuilder

  defp sheet_record!(%SheetRecord{} = sheet), do: sheet
  defp sheet_record!(%{id: sheet_id}), do: Repo.get!(SheetRecord, sheet_id)
end
