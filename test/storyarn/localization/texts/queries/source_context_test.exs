defmodule Storyarn.Localization.Texts.Queries.SourceContextTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project}
  end

  describe "text_source_context/1" do
    test "names the flow and excerpts the dialogue of a node text", %{project: project} do
      flow = flow_fixture(project, %{name: "Harbor"})

      node =
        node_fixture(flow, %{data: %{"speaker" => "Louise", "text" => "Welcome aboard, {player_name}."}})

      text = localized_text_fixture(project.id, %{source_id: node.id, source_text: "Welcome aboard"})

      assert %{
               kind: :flow_node,
               parent_name: "Harbor",
               label: "Welcome aboard, {player_name}.",
               flow_id: flow_id,
               node_id: node_id,
               sheet_id: nil
             } = Localization.text_source_context(text)

      assert flow_id == flow.id
      assert node_id == node.id
    end

    test "prefers an explicit node label over the text excerpt", %{project: project} do
      flow = flow_fixture(project, %{name: "Harbor"})
      node = node_fixture(flow, %{data: %{"label" => "Welcome", "text" => "Welcome aboard."}})
      text = localized_text_fixture(project.id, %{source_id: node.id})

      assert %{label: "Welcome"} = Localization.text_source_context(text)
    end

    test "names the sheet and variable of a block text", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Ruby"})

      block =
        block_fixture(sheet, %{variable_name: "harbor_gate", value: %{"content" => "Harbor gate"}})

      text =
        localized_text_fixture(project.id, %{
          source_type: "block",
          source_id: block.id,
          source_text: "Harbor gate"
        })

      assert %{kind: :block, parent_name: "Ruby", label: "harbor_gate", sheet_id: sheet_id} =
               Localization.text_source_context(text)

      assert sheet_id == sheet.id
    end

    test "names the sheet of a speaker-name text", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Ruby"})

      text =
        localized_text_fixture(project.id, %{
          source_type: "sheet",
          source_field: "name",
          source_id: sheet.id,
          source_text: "Ruby"
        })

      assert %{kind: :sheet, parent_name: "Ruby", label: nil, sheet_id: sheet_id} =
               Localization.text_source_context(text)

      assert sheet_id == sheet.id
    end

    test "returns nil when the source no longer exists", %{project: project} do
      text = localized_text_fixture(project.id, %{source_id: 999_999_999})

      assert Localization.text_source_context(text) == nil
    end
  end
end
