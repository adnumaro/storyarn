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

      content = LiveVue.Test.get_vue(view, name: "live/docs/show/Content")
      assert content.props["guide-body"] =~ "narrative design platform"
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
