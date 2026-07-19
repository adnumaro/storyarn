defmodule StoryarnWeb.SheetLive.Handlers.ReferenceHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Reference Source"})
    target_sheet = sheet_fixture(project, %{name: "Reference Target"})

    block =
      block_fixture(sheet, %{
        type: "reference",
        config: %{"allowed_types" => ["sheet"], "label" => "Reference"},
        value: %{}
      })

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{block: block, project: project, sheet: sheet, target_sheet: target_sheet, url: url}
  end

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end

  describe "select_reference event" do
    test "stores a valid reference target", %{conn: conn, block: block, target_sheet: target_sheet, url: url} do
      view = mount_sheet(conn, url)

      render_hook(view, "select_reference", %{
        "block-id" => to_string(block.id),
        "type" => "sheet",
        "id" => to_string(target_sheet.id)
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["target_type"] == "sheet"
      assert updated_block.value["target_id"] == target_sheet.id
    end

    test "ignores references for blocks outside the current sheet", %{
      conn: conn,
      project: project,
      target_sheet: target_sheet,
      url: url
    } do
      other_sheet = sheet_fixture(project, %{name: "Other Source"})
      other_block = block_fixture(other_sheet, %{type: "reference", value: %{}})
      view = mount_sheet(conn, url)

      render_hook(view, "select_reference", %{
        "block-id" => to_string(other_block.id),
        "type" => "sheet",
        "id" => to_string(target_sheet.id)
      })

      updated_block = Sheets.get_block(other_block.id)
      assert updated_block.value == other_block.value
    end
  end
end
