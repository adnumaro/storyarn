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
      assert content.props["guide-body"] =~ "/images/docs/project-dashboard-current.png"
      assert content.props["guide-body"] =~ "/images/docs/scenes-dashboard.png"
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

      assert welcome_guides == [
               "Start Here",
               "What is Storyarn?",
               "Core Concepts",
               "Core Workflow",
               "Command Palette"
             ]

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
               "Debug Mode",
               "Structural Analysis"
             ]

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")
      assert content.props["guide-body"] =~ "Dialogue responses"
      assert content.props["guide-body"] =~ "/docs/narrative-design/instruction-editor"
    end

    test "renders project management guides in navigation order", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/project-management/project-dashboard")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert Enum.any?(docs["categories"], &(&1["label"] == "Project Management"))

      project_management_guides =
        docs["guides"]
        |> Enum.filter(&(&1["category"] == "project-management"))
        |> Enum.map(& &1["title"])

      assert project_management_guides == [
               "Project Dashboard",
               "Assets",
               "Project Templates",
               "Project Settings",
               "Snapshots and Trash"
             ]
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

    test "renders Spanish docs with localized navigation and canonical metadata", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "en"})
      {:ok, view, _html} = live(conn, "/es/docs/narrative-design/condition-editor")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      assert docs["currentLocale"] == "es"
      assert docs["urls"]["home"] == "/es"
      assert docs["urls"]["docs"] == "/es/docs"
      assert docs["guide"]["title"] == "Editor de Condiciones"
      assert docs["guide"]["url"] == "/es/docs/narrative-design/condition-editor"

      assert docs["languageLinks"] == [
               %{
                 "flagCode" => "gb",
                 "label" => "English",
                 "languageTag" => "en",
                 "locale" => "en",
                 "path" => "/docs/narrative-design/condition-editor",
                 "shortLabel" => "EN"
               },
               %{
                 "flagCode" => "es",
                 "label" => "Español",
                 "languageTag" => "es",
                 "locale" => "es",
                 "path" => "/es/docs/narrative-design/condition-editor",
                 "shortLabel" => "ES"
               }
             ]

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/DocsContent")

      assert content.props["guide-body"] =~
               ~s(href="/es/docs/narrative-design/instruction-editor")

      metadata = seo_metadata(view)
      assert metadata["locale"] == "es"
      assert URI.parse(metadata["canonical_url"]).path == "/es/docs/narrative-design/condition-editor"
      assert Enum.map(metadata["alternate_links"], & &1["hreflang"]) == ["en", "es", "x-default"]
    end

    test "does not serve an English guide under a missing Spanish URL", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, "/es/docs/not-a-category/not-a-guide")
      end
    end
  end

  defp seo_metadata(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#live-seo-metadata")
    |> LazyHTML.attribute("data-metadata")
    |> List.first()
    |> Jason.decode!()
  end
end
