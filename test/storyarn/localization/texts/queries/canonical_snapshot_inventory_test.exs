defmodule Storyarn.Localization.Texts.Queries.CanonicalSnapshotInventoryTest do
  use Storyarn.DataCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Localization.Texts.Data.FlowNodeRecord
  alias Storyarn.Repo

  test "lists every active row deterministically without engine source or locale filtering" do
    project = project_fixture()

    archived_locale = language_fixture(project, %{locale_code: "fr", name: "French"})
    assert {:ok, _archived_locale} = Localization.remove_language(archived_locale)

    flow = flow_fixture(project)
    deleted_node = node_fixture(flow)
    assert {:ok, _deleted_node, _meta} = Flows.delete_node(deleted_node)

    wrong_type_sheet = sheet_without_flow_node_id(project)
    base_id = 1_000_000_000 + project.id * 10

    active_rows = [
      localized_text_fixture(project.id, %{source_id: base_id + 1, locale_code: "es"}),
      localized_text_fixture(project.id, %{source_id: deleted_node.id, locale_code: "de"}),
      localized_text_fixture(project.id, %{source_id: wrong_type_sheet.id, locale_code: "it"}),
      localized_text_fixture(project.id, %{
        source_type: "sheet",
        source_id: base_id + 2,
        source_field: "name",
        locale_code: "zz"
      }),
      localized_text_fixture(project.id, %{
        source_type: "block",
        source_id: base_id + 3,
        locale_code: "fr"
      })
    ]

    archived_row =
      localized_text_fixture(project.id, %{
        source_type: "block",
        source_id: base_id + 4,
        locale_code: "pt"
      })

    assert {1, nil} =
             Localization.delete_texts_for_source(archived_row.source_type, archived_row.source_id)

    foreign_project = project_fixture()

    foreign_row =
      localized_text_fixture(foreign_project.id, %{
        source_id: base_id + 5,
        locale_code: "nl"
      })

    expected_ids =
      active_rows
      |> Enum.sort_by(&{&1.source_type, &1.source_id, &1.source_field, &1.locale_code, &1.id})
      |> Enum.map(& &1.id)

    captured = Localization.list_texts_for_canonical_snapshot(project.id)
    captured_ids = Enum.map(captured, & &1.id)

    assert captured_ids == expected_ids
    refute archived_row.id in captured_ids
    refute foreign_row.id in captured_ids

    assert Localization.list_texts_for_canonical_snapshot(project.id) == captured
    assert Localization.list_texts_for_export(project.id, ~w(de es fr it zz)) == []
  end

  defp sheet_without_flow_node_id(project) do
    sheet = sheet_fixture(project)

    if Repo.get(FlowNodeRecord, sheet.id),
      do: sheet_without_flow_node_id(project),
      else: sheet
  end
end
