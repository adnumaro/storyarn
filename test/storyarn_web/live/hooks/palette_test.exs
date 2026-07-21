defmodule StoryarnWeb.Live.Hooks.PaletteTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  defmodule TestAdapter do
    @moduledoc false
    # Runs in the LiveView process, so the test pid travels via app env,
    # not the process dictionary.
    def capture(payload) do
      send(Application.get_env(:storyarn, :analytics_test_pid), {:analytics_capture, payload})
      :ok
    end

    def identify(_payload), do: :ok
  end

  setup %{conn: conn} do
    original_adapter = Application.get_env(:storyarn, :analytics_adapter)

    Application.put_env(:storyarn, :analytics_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAdapter)

    on_exit(fn ->
      Application.delete_env(:storyarn, :analytics_test_pid)

      if original_adapter do
        Application.put_env(:storyarn, :analytics_adapter, original_adapter)
      else
        Application.delete_env(:storyarn, :analytics_adapter)
      end
    end)

    user = user_fixture()
    conn = log_in_user(conn, user)
    {:error, {:live_redirect, %{to: workspace_path}}} = live(conn, ~p"/workspaces")
    {:ok, view, _html} = live(conn, workspace_path)

    {:ok, view: view, user: user}
  end

  test "palette_opened tracks the allowlisted event with its surface", %{view: view} do
    render_hook(view, "palette_opened", %{"surface" => "workspace"})

    assert_receive {:analytics_capture, %{event: "palette opened"} = payload}
    assert payload.properties["surface"] == "workspace"
  end

  test "palette_command_executed tracks command_id and surface", %{view: view} do
    render_hook(view, "palette_command_executed", %{
      "command_id" => "workspace.toggle-sidebar",
      "surface" => "workspace"
    })

    assert_receive {:analytics_capture, %{event: "palette command executed"} = payload}
    assert payload.properties["command_id"] == "workspace.toggle-sidebar"
    assert payload.properties["surface"] == "workspace"
  end

  test "palette_search_no_results tracks the query length, never content", %{view: view} do
    render_hook(view, "palette_search_no_results", %{
      "query_length" => 7,
      "surface" => "workspace"
    })

    assert_receive {:analytics_capture, %{event: "palette search no results"} = payload}
    assert payload.properties["query_length"] == 7
    refute Map.has_key?(payload.properties, "query")
  end

  test "payloads are rebuilt from validated params — extra client keys never pass through",
       %{view: view} do
    render_hook(view, "palette_opened", %{
      "surface" => "workspace",
      "query" => "secret story content",
      "injected" => "nope"
    })

    assert_receive {:analytics_capture, %{event: "palette opened"} = payload}
    assert Map.keys(payload.properties) == ["surface"]
  end

  describe "palette_nav" do
    test "replies grouped authorized destinations with URLs and echoes the token",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace, name: "Veilbreak"})
      sheet = sheet_fixture(project, %{name: "Kael the Wanderer"})

      render_hook(view, "palette_nav", %{"query" => "kael", "token" => 7})

      assert_reply(view, %{token: 7, groups: groups})

      entities = Enum.find(groups, &(&1.key == "entities"))
      assert [item] = entities.items
      assert item.id == "nav.sheet.#{sheet.id}"
      assert item.type == "sheet"
      assert item.label == "Kael the Wanderer"
      assert item.context == "Veilbreak"
      assert item.url == "/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
    end

    test "empty query lists workspaces, projects, and per-project settings",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace, name: "Veilbreak"})

      render_hook(view, "palette_nav", %{"query" => "", "token" => 1})

      assert_reply(view, %{token: 1, groups: groups})
      keys = Enum.map(groups, & &1.key)
      assert "workspaces" in keys
      assert "projects" in keys
      assert "project_settings" in keys
      assert "workspace_settings" in keys
      refute "entities" in keys

      settings = Enum.find(groups, &(&1.key == "project_settings"))

      assert Enum.any?(
               settings.items,
               &(&1.url == "/workspaces/#{workspace.slug}/projects/#{project.slug}/settings")
             )

      workspace_settings = Enum.find(groups, &(&1.key == "workspace_settings"))

      assert Enum.any?(
               workspace_settings.items,
               &(&1.url == "/users/settings/workspaces/#{workspace.slug}/general")
             )
    end

    test "never leaks another user's destinations", %{view: view} do
      intruder_target = user_fixture()
      other_workspace = workspace_fixture(intruder_target)
      other_project = project_fixture(intruder_target, %{workspace: other_workspace})
      sheet_fixture(other_project, %{name: "LeakMe Secret"})

      render_hook(view, "palette_nav", %{"query" => "LeakMe", "token" => 3})

      assert_reply(view, %{token: 3, groups: groups})
      assert groups == []
    end
  end
end
