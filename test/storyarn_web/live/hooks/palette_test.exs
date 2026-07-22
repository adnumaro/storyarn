defmodule StoryarnWeb.Live.Hooks.PaletteTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
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

    {:ok, view: view, user: user, conn: conn, workspace_path: workspace_path}
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

  test "registered AI command ids use the canonical task catalog", %{view: view} do
    render_hook(view, "palette_command_executed", %{
      "command_id" => "ai.contract.echo",
      "surface" => "flows"
    })

    assert_receive {:analytics_capture, %{event: "palette command executed"} = payload}
    assert payload.properties["command_id"] == "ai.contract.echo"
    assert payload.properties["surface"] == "flows"
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

  test "free-text command_id is never persisted to analytics", %{view: view} do
    render_hook(view, "palette_command_executed", %{
      "command_id" => "mi historia secreta con espacios",
      "surface" => "workspace"
    })

    # Hyphenated forged text passes a character-shape check but not the
    # exact static/nav allowlist.
    render_hook(view, "palette_command_executed", %{
      "command_id" => "mi-historia-secreta-con-guiones",
      "surface" => "workspace"
    })

    # Leading zeros are never emitted by nav_item/1 — forged variants of a
    # canonical id must not inflate analytics cardinality.
    render_hook(view, "palette_command_executed", %{
      "command_id" => "nav.sheet.007",
      "surface" => "workspace"
    })

    refute_receive {:analytics_capture, %{event: "palette command executed"}}, 100
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
      assert item.context == "Veilbreak · #{workspace.name}"
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

    test "workspace settings appear for owners and admins, never plain members",
         %{view: view, user: user} do
      other_owner = user_fixture()
      member_workspace = workspace_fixture(other_owner)
      admin_workspace = workspace_fixture(user_fixture())
      Storyarn.Workspaces.create_membership(member_workspace.id, user.id, "member")
      Storyarn.Workspaces.create_membership(admin_workspace.id, user.id, "admin")

      render_hook(view, "palette_nav", %{"query" => "", "token" => 5})

      assert_reply(view, %{token: 5, groups: groups})

      workspaces = Enum.find(groups, &(&1.key == "workspaces"))
      assert Enum.any?(workspaces.items, &(&1.id == "nav.workspace.#{member_workspace.id}"))

      workspace_settings = Enum.find(groups, &(&1.key == "workspace_settings"))

      refute Enum.any?(
               workspace_settings.items,
               &(&1.id == "nav.workspace-settings.#{member_workspace.id}")
             )

      # Same criterion as the settings pages (:access_workspace_settings).
      assert Enum.any?(
               workspace_settings.items,
               &(&1.id == "nav.workspace-settings.#{admin_workspace.id}")
             )
    end

    test "project settings appear only for project owners", %{view: view, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      editor_project = project_fixture(owner, %{workspace: workspace, name: "Editor project"})
      viewer_project = project_fixture(owner, %{workspace: workspace, name: "Viewer project"})
      membership_fixture(editor_project, user, "editor")
      membership_fixture(viewer_project, user, "viewer")

      render_hook(view, "palette_nav", %{"query" => "", "token" => 6})

      assert_reply(view, %{token: 6, groups: groups})
      projects = Enum.find(groups, &(&1.key == "projects"))
      settings_items = Enum.find_value(groups, [], fn group -> if group.key == "project_settings", do: group.items end)

      assert Enum.any?(projects.items, &(&1.id == "nav.project.#{editor_project.id}"))
      assert Enum.any?(projects.items, &(&1.id == "nav.project.#{viewer_project.id}"))
      refute Enum.any?(settings_items, &(&1.id == "nav.project-settings.#{editor_project.id}"))
      refute Enum.any?(settings_items, &(&1.id == "nav.project-settings.#{viewer_project.id}"))
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

  describe "palette_create_targets" do
    test "replies editable projects only, with workspace context", %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace, name: "Veilbreak"})

      viewer_owner = user_fixture()
      viewer_project = project_fixture(viewer_owner, %{workspace: workspace_fixture(viewer_owner)})
      membership_fixture(viewer_project, user, "viewer")

      render_hook(view, "palette_create_targets", %{"token" => 4})

      assert_reply(view, %{token: 4, projects: projects})
      assert Enum.any?(projects, &(&1.id == project.id and &1.label == "Veilbreak" and &1.context == workspace.name))
      refute Enum.any?(projects, &(&1.id == viewer_project.id))
    end
  end

  describe "palette_create" do
    test "creates the entity in an authorized project and replies its URL", %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project:#{project.id}:shell")

      render_hook(view, "palette_create", %{
        "type" => "sheet",
        "project_id" => project.id,
        "operation_id" => "create-sheet-1"
      })

      assert_reply(view, %{url: url})
      assert [_, sheet_id] = Regex.run(~r{/sheets/(\d+)$}, url)
      assert url == "/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet_id}"

      sheet = Storyarn.Sheets.get_sheet(project.id, String.to_integer(sheet_id))
      assert sheet.name == "Untitled"

      # Sidebars refresh through the same shell-topic message the tree emits.
      assert_receive {:tree_changed, :sheets}
    end

    test "synchronizes localization inventory after creating a sheet", %{view: view, user: user} do
      project = project_fixture(user, %{workspace: workspace_fixture(user)})
      language_fixture(project)

      render_hook(view, "palette_create", %{
        "type" => "sheet",
        "project_id" => project.id,
        "operation_id" => "create-localized-sheet"
      })

      assert_reply(view, %{url: url})
      assert [_, sheet_id] = Regex.run(~r{/sheets/(\d+)$}, url)

      assert [%{source_field: "name", source_text: "Untitled", locale_code: "es"}] =
               Storyarn.Localization.get_texts_for_source("sheet", String.to_integer(sheet_id))
    end

    test "creates flows and scenes through their domain facades", %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project:#{project.id}:shell")

      for {type, path, tree_key} <- [{"flow", "flows", :flows}, {"scene", "scenes", :scenes}] do
        render_hook(view, "palette_create", %{
          "type" => type,
          "project_id" => project.id,
          "operation_id" => "create-#{type}-1"
        })

        assert_reply(view, %{url: url})
        assert url =~ "/workspaces/#{workspace.slug}/projects/#{project.slug}/#{path}/"
        assert_receive {:tree_changed, ^tree_key}
      end
    end

    test "replaying an operation id returns the original result without creating twice",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      payload = %{"type" => "sheet", "project_id" => project.id, "operation_id" => "stable-create-id"}

      render_hook(view, "palette_create", payload)
      assert_reply(view, %{url: first_url})
      render_hook(view, "palette_create", payload)
      assert_reply(view, %{url: second_url})

      assert first_url == second_url
      assert length(Storyarn.Sheets.search_sheets_in_projects([project.id], "")) == 1
    end

    test "replaying after a LiveView reconnect returns the durable create result",
         %{view: view, user: user, conn: conn, workspace_path: workspace_path} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      payload = %{"type" => "sheet", "project_id" => project.id, "operation_id" => "reconnected-create-id"}

      render_hook(view, "palette_create", payload)
      assert_reply(view, %{url: first_url})

      {:ok, reconnected_view, _html} = live(conn, workspace_path)
      render_hook(reconnected_view, "palette_create", payload)
      assert_reply(reconnected_view, %{url: second_url})

      assert first_url == second_url
      assert length(Storyarn.Sheets.search_sheets_in_projects([project.id], "")) == 1
    end

    test "rejects a project the user cannot edit — nothing is created", %{view: view, user: user} do
      viewer_owner = user_fixture()
      viewer_project = project_fixture(viewer_owner, %{workspace: workspace_fixture(viewer_owner)})
      membership_fixture(viewer_project, user, "viewer")

      render_hook(view, "palette_create", %{
        "type" => "flow",
        "project_id" => viewer_project.id,
        "operation_id" => "unauthorized-create"
      })

      assert_reply(view, %{error: "unauthorized"})
      assert Storyarn.Flows.search_flows_in_projects([viewer_project.id], "") == []
    end
  end

  describe "palette_delete_search" do
    test "lists deletable entities with their project id; empty query browses recents",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace, name: "Veilbreak"})
      sheet = sheet_fixture(project, %{name: "Kael the Wanderer"})

      viewer_owner = user_fixture()
      viewer_project = project_fixture(viewer_owner, %{workspace: workspace_fixture(viewer_owner)})
      membership_fixture(viewer_project, user, "viewer")
      readonly = sheet_fixture(viewer_project, %{name: "Readonly Relic"})

      render_hook(view, "palette_delete_search", %{"query" => "", "token" => 9})

      assert_reply(view, %{token: 9, items: items})
      hit = Enum.find(items, &(&1.id == sheet.id and &1.type == "sheet"))
      assert hit.label == "Kael the Wanderer"
      assert hit.context == "Veilbreak · #{workspace.name}"
      assert hit.projectId == project.id
      refute Enum.any?(items, &(&1.id == readonly.id and &1.type == "sheet"))
    end
  end

  describe "palette_delete" do
    test "soft-deletes an authorized entity and broadcasts the full typed subtree",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project)
      child = sheet_fixture(project, %{parent_id: sheet.id})
      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project:#{project.id}:shell")

      render_hook(view, "palette_delete", %{
        "type" => "sheet",
        "id" => sheet.id,
        "project_id" => project.id,
        "operation_id" => "delete-sheet-1"
      })

      assert_reply(view, %{deleted: true})
      assert Storyarn.Sheets.get_sheet(project.id, sheet.id) == nil
      assert Storyarn.Sheets.get_sheet(project.id, child.id) == nil

      # Same messages the sidebar delete path emits: typed and carrying every
      # cascade-deleted id, so only editors of THESE entities navigate away.
      assert_receive {:entities_deleted, :sheet, deleted_ids}
      assert Enum.sort(deleted_ids) == Enum.sort([sheet.id, child.id])
      assert_receive {:tree_changed, :sheets}
    end

    test "an id beyond the bigint range is rejected before reaching the database",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project)

      render_hook(view, "palette_delete", %{
        "type" => "sheet",
        "id" => 9_223_372_036_854_775_808,
        "project_id" => project.id,
        "operation_id" => "oversized-delete"
      })

      assert_reply(view, %{error: "invalid_request"})

      assert %{} = Storyarn.Sheets.get_sheet(project.id, sheet.id)
    end

    test "rejects view-only and mismatched ids — nothing is deleted", %{view: view, user: user} do
      viewer_owner = user_fixture()
      viewer_project = project_fixture(viewer_owner, %{workspace: workspace_fixture(viewer_owner)})
      membership_fixture(viewer_project, user, "viewer")
      readonly_sheet = sheet_fixture(viewer_project)

      render_hook(view, "palette_delete", %{
        "type" => "sheet",
        "id" => readonly_sheet.id,
        "project_id" => viewer_project.id,
        "operation_id" => "readonly-delete"
      })

      assert_reply(view, %{error: "unauthorized"})
      assert %{} = Storyarn.Sheets.get_sheet(viewer_project.id, readonly_sheet.id)

      # An editable project cannot be used as a doorway to another project's entity.
      workspace = workspace_fixture(user)
      own_project = project_fixture(user, %{workspace: workspace})

      render_hook(view, "palette_delete", %{
        "type" => "sheet",
        "id" => readonly_sheet.id,
        "project_id" => own_project.id,
        "operation_id" => "mismatched-delete"
      })

      assert_reply(view, %{error: "not_found"})
      assert %{} = Storyarn.Sheets.get_sheet(viewer_project.id, readonly_sheet.id)
    end

    test "soft-deletes flows and scenes", %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      flow = flow_fixture(project)
      scene = scene_fixture(project)

      for {type, entity} <- [{"flow", flow}, {"scene", scene}] do
        render_hook(view, "palette_delete", %{
          "type" => type,
          "id" => entity.id,
          "project_id" => project.id,
          "operation_id" => "delete-#{type}-1"
        })

        assert_reply(view, %{deleted: true})
      end

      assert Storyarn.Flows.get_flow(project.id, flow.id) == nil
      assert Storyarn.Scenes.get_scene(project.id, scene.id) == nil
    end

    test "refreshes open flows that referenced a deleted flow", %{view: view, user: user} do
      project = project_fixture(user, %{workspace: workspace_fixture(user)})
      host_flow = flow_fixture(project)
      target_flow = flow_fixture(project)

      {:ok, _subflow} =
        Storyarn.Flows.create_node(host_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => target_flow.id}
        })

      Storyarn.Collaboration.subscribe_changes({:flow, host_flow.id})

      render_hook(view, "palette_delete", %{
        "type" => "flow",
        "id" => target_flow.id,
        "project_id" => project.id,
        "operation_id" => "delete-referenced-flow"
      })

      assert_reply(view, %{deleted: true})

      assert_receive {:remote_change, :flow_refresh, %{user_id: 0, user_email: "System", user_color: "#666"}}
    end

    test "replaying after a LiveView reconnect returns the durable delete result",
         %{view: view, user: user, conn: conn, workspace_path: workspace_path} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project)

      payload = %{
        "type" => "sheet",
        "id" => sheet.id,
        "project_id" => project.id,
        "operation_id" => "reconnected-delete-id"
      }

      render_hook(view, "palette_delete", payload)
      assert_reply(view, %{deleted: true})

      {:ok, reconnected_view, _html} = live(conn, workspace_path)
      render_hook(reconnected_view, "palette_delete", payload)
      assert_reply(reconnected_view, %{deleted: true})

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id) == nil
    end
  end

  test "malformed known palette events fail closed without reaching the host LiveView", %{view: view} do
    invalid_events = [
      {"palette_nav", %{"query" => "test", "token" => "bad"}},
      {"palette_create_targets", %{"token" => "bad"}},
      {"palette_create", %{"type" => "sheet", "project_id" => 1}},
      {"palette_delete_search", %{"query" => 123, "token" => 1}},
      {"palette_delete", %{"type" => "sheet", "id" => 1, "project_id" => 1}},
      {"palette_opened", %{"surface" => "forged"}},
      {"palette_command_executed", %{"command_id" => 123, "surface" => "workspace"}},
      {"palette_search_no_results", %{"query_length" => -1, "surface" => "workspace"}}
    ]

    for {event, payload} <- invalid_events do
      render_hook(view, event, payload)
      assert_reply(view, %{error: "invalid_request"})
    end
  end
end
