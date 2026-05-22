defmodule StoryarnWeb.DocsLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Show" do
    test "renders docs through the LiveVue docs layout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/welcome/what-is-storyarn")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert docs["guide"]["title"] == "What is Storyarn?"
      assert docs["guide"]["url"] == "/docs/welcome/what-is-storyarn"
      assert [%{"label" => "Welcome"} | _] = docs["categories"]

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")
      assert content.props["guide-body"] =~ "narrative design platform"
      assert content.props["guide-body"] =~ "/images/docs/project-dashboard.webp"
      assert content.props["guide-body"] =~ "/images/docs/scenes.webp"
      refute content.props["guide-body"] =~ "veilbreak-"
    end

    test "renders start here as the first welcome guide", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/welcome/start-here")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert docs["guide"]["title"] == "Start Here"
      assert docs["guide"]["url"] == "/docs/welcome/start-here"

      assert [%{"label" => "Welcome"} | _] = docs["categories"]
      assert [%{"title" => "Start Here", "url" => "/docs/welcome/start-here"} | _] = docs["guides"]

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")
      assert content.props["guide-body"] =~ "Pick your path"
      assert content.props["guide-body"] =~ "localization manager"
    end

    test "renders core concepts glossary in welcome navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/welcome/core-concepts")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert docs["guide"]["title"] == "Core Concepts"
      assert docs["guide"]["url"] == "/docs/welcome/core-concepts"

      welcome_guides =
        docs["guides"]
        |> Enum.filter(&(&1["category"] == "welcome"))
        |> Enum.map(& &1["title"])

      assert welcome_guides == ["Start Here", "What is Storyarn?", "Core Concepts", "Core Workflow"]

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")
      assert content.props["guide-body"] =~ "Workspace"
      assert content.props["guide-body"] =~ "Localization ID"
    end

    test "quick start reaches preview and export", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/quick-start/first-flow")

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")

      assert content.props["guide-body"] =~ "Preview with the Story Player"
      assert content.props["guide-body"] =~ "Export the project"
      assert content.props["guide-body"] =~ "Completion checklist"
    end

    test "renders nested guide sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/narrative-design/node-types/dialogue")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert docs["guide"]["title"] == "Dialogue Nodes"
      assert docs["guide"]["url"] == "/docs/narrative-design/node-types/dialogue"
      assert docs["guide"]["section"] == "node-types"
      assert docs["guide"]["sectionLabel"] == "Node Types"

      node_types =
        docs["guides"]
        |> Enum.filter(&(&1["category"] == "narrative-design" && &1["section"] == "node-types"))
        |> Enum.map(& &1["title"])

      assert node_types == [
               "Entry & Exit Nodes",
               "Dialogue Nodes",
               "Condition Nodes",
               "Instruction Nodes",
               "Hub & Jump Nodes",
               "Subflow Nodes",
               "Sequence Nodes",
               "Annotation Nodes"
             ]
    end

    test "renders reusable condition and instruction editor guides", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/narrative-design/condition-editor")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert docs["guide"]["title"] == "Condition Editor"
      assert docs["guide"]["section"] == nil
      assert docs["guide"]["url"] == "/docs/narrative-design/condition-editor"

      narrative_root_guides =
        docs["guides"]
        |> Enum.filter(&(&1["category"] == "narrative-design" && is_nil(&1["section"])))
        |> Enum.map(& &1["title"])

      assert narrative_root_guides == [
               "Flows Overview",
               "Condition Editor",
               "Instruction Editor",
               "Debug Mode"
             ]

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")
      assert content.props["guide-body"] =~ "Dialogue responses"
      assert content.props["guide-body"] =~ "/docs/narrative-design/instruction-editor"
    end

    test "updates search props from the LiveVue layout event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/welcome/what-is-storyarn")

      render_change(view, "search", %{"query" => "flow"})

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      search = layout.props["docs"]["search"]

      assert search["query"] == "flow"
      assert is_list(search["results"])
      assert Enum.any?(search["results"], &(&1["title"] =~ "Flow"))
    end
  end
end
