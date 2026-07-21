defmodule StoryarnWeb.DocsGatingTest do
  # async: false — global flag state + FunWithFlags ETS cache require explicit
  # enable/disable per test block, not sandbox-only cleanup.
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Storyarn.Docs

  describe "flag-gated AI docs with :ai_integrations OFF (default)" do
    test "direct URL is unreachable (404)", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/docs/ai/overview") end
    end

    test "guide navigation indexes exclude the AI category and its guides", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/welcome/start-here")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      docs = layout.props["docs"]

      refute Enum.any?(docs["categories"], fn category -> category["label"] == "AI" end)
      refute Enum.any?(docs["guides"], fn guide -> String.contains?(guide["url"], "/docs/ai/") end)
    end

    test "search never returns flag-hidden guides" do
      assert Docs.search("AI in Storyarn") == []
      refute Enum.any?(Docs.search("AI"), &(&1.category == "ai"))
    end

    test "prev/next navigation skips flag-hidden guides" do
      last_visible = Docs.list_guides() |> List.last()
      assert last_visible.category != "ai"

      {_prev, next} = Docs.prev_next(last_visible.category, Enum.join(last_visible.path, "/"))
      assert next == nil
    end

    test "sitemap.xml excludes AI docs URLs", %{conn: conn} do
      body = conn |> get("/sitemap.xml") |> response(200)
      refute body =~ "/docs/ai/"
    end

    test "llms.txt excludes AI docs URLs", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)
      refute body =~ "/docs/ai/"
    end
  end

  describe "flag-gated AI docs with :ai_integrations ON globally" do
    setup do
      FunWithFlags.enable(:ai_integrations)
      on_exit(fn -> FunWithFlags.disable(:ai_integrations) end)
      :ok
    end

    test "direct URL renders the AI guide", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/ai/overview")

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/docs/Layout")
      assert layout.props["docs"]["guide"]["title"] == "AI in Storyarn"
    end

    test "indexes, search, sitemap, and llms.txt include the AI docs", %{conn: conn} do
      assert Enum.any?(Docs.list_categories(), fn {category, _label} -> category == "ai" end)
      assert Enum.any?(Docs.search("AI in Storyarn"), &(&1.category == "ai"))

      sitemap = conn |> get("/sitemap.xml") |> response(200)
      assert sitemap =~ "/docs/ai/overview"

      llms = conn |> get("/llms.txt") |> response(200)
      assert llms =~ "/docs/ai/overview"
    end

    test "prev/next reaches the AI guide from its visible neighbor" do
      guides = Docs.list_guides()
      ai_index = Enum.find_index(guides, &(&1.category == "ai"))
      assert ai_index

      neighbor = Enum.at(guides, ai_index - 1)
      {_prev, next} = Docs.prev_next(neighbor.category, Enum.join(neighbor.path, "/"))
      assert next.category == "ai"
    end
  end
end
