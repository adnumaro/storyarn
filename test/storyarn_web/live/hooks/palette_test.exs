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

  alias Storyarn.CommandPalette.Definition
  alias Storyarn.Notifications

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

  test "operation lifecycle analytics accepts only registered operation ids and content-free properties",
       %{view: view} do
    events = [
      {"palette_operation_selected", "palette operation selected"},
      {"palette_operation_completed", "palette operation completed"},
      {"palette_operation_abandoned", "palette operation abandoned"}
    ]

    for {hook_event, analytics_event} <- events do
      render_hook(view, hook_event, %{
        "operation_id" => "create",
        "surface" => "workspace",
        "query" => "secret story content",
        "parameter_values" => %{"project" => 123}
      })

      assert_receive {:analytics_capture, %{event: ^analytics_event} = payload}
      assert payload.properties["operation_id"] == "create"
      assert payload.properties["surface"] == "workspace"
      assert Enum.sort(Map.keys(payload.properties)) == ["operation_id", "surface"]
    end
  end

  test "operation lifecycle analytics ignores ids outside the registry", %{view: view} do
    for hook_event <-
          ~w(palette_operation_selected palette_operation_completed palette_operation_abandoned) do
      render_hook(view, hook_event, %{
        "operation_id" => "forged_story_content",
        "surface" => "workspace"
      })
    end

    refute_receive {:analytics_capture, %{event: "palette operation selected"}}, 100
    refute_receive {:analytics_capture, %{event: "palette operation completed"}}, 100
    refute_receive {:analytics_capture, %{event: "palette operation abandoned"}}, 100
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

    test "workspace general settings appear for owners, admins, and members",
         %{view: view, user: user} do
      other_owner = user_fixture()
      member_workspace = workspace_fixture(other_owner)
      admin_workspace = workspace_fixture(user_fixture())
      viewer_workspace = workspace_fixture(user_fixture())
      Storyarn.Workspaces.create_membership(member_workspace.id, user.id, "member")
      Storyarn.Workspaces.create_membership(admin_workspace.id, user.id, "admin")
      Storyarn.Workspaces.create_membership(viewer_workspace.id, user.id, "viewer")

      render_hook(view, "palette_nav", %{"query" => "", "token" => 5})

      assert_reply(view, %{token: 5, groups: groups})

      workspaces = Enum.find(groups, &(&1.key == "workspaces"))
      assert Enum.any?(workspaces.items, &(&1.id == "nav.workspace.#{member_workspace.id}"))

      workspace_settings = Enum.find(groups, &(&1.key == "workspace_settings"))

      assert Enum.any?(
               workspace_settings.items,
               &(&1.id == "nav.workspace-settings.#{member_workspace.id}")
             )

      # Same criterion as the read-only general settings page.
      assert Enum.any?(
               workspace_settings.items,
               &(&1.id == "nav.workspace-settings.#{admin_workspace.id}")
             )

      refute Enum.any?(
               workspace_settings.items,
               &(&1.id == "nav.workspace-settings.#{viewer_workspace.id}")
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

  describe "palette_advanced_search" do
    test "is unavailable outside a project context and preserves the request token",
         %{view: view} do
      render_hook(view, "palette_advanced_search", %{
        "query" => "#kael",
        "submitted" => false,
        "token" => 21
      })

      assert_reply(view, %{token: 21, error: "unavailable"})
    end

    test "returns explicit completion and navigation actions for a hierarchy",
         %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      root = sheet_fixture(project, %{name: "Main Characters", shortcut: "main-characters"})

      branch =
        sheet_fixture(project, %{
          name: "Companions",
          shortcut: "companions",
          parent_id: root.id,
          position: 0
        })

      leaf =
        sheet_fixture(project, %{
          name: "Kael",
          shortcut: "kael",
          parent_id: root.id,
          position: 1
        })

      _grandchild =
        sheet_fixture(project, %{
          name: "Mira",
          shortcut: "mira",
          parent_id: branch.id
        })

      view = project_view(conn, workspace, project)

      render_hook(view, "palette_advanced_search", %{
        "query" => "#main-characters.",
        "submitted" => false,
        "token" => 22
      })

      assert_reply(view, %{token: 22, mode: "sheets", items: items, truncated: false})

      assert Enum.find(items, &(&1.id == "sheet:#{branch.id}")).action == %{
               kind: "complete",
               value: "#main-characters.companions."
             }

      assert Enum.find(items, &(&1.id == "sheet:#{leaf.id}")).action == %{
               kind: "navigate",
               url: "/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{leaf.id}"
             }
    end

    test "keeps full search submit-only and searches authored nested content",
         %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project, %{name: "Archive", shortcut: "archive"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Relic"},
          value: %{"content" => "The ancient tome is sealed"}
        })

      view = project_view(conn, workspace, project)
      payload = %{"query" => "*ancient tome", "submitted" => false, "token" => 23}

      render_hook(view, "palette_advanced_search", payload)
      assert_reply(view, %{token: 23, error: "not_submitted"})

      render_hook(view, "palette_advanced_search", %{payload | "submitted" => true, "token" => 24})

      assert_reply(view, %{token: 24, mode: "all", items: items})

      assert Enum.any?(items, fn item ->
               item.id == "sheet:#{sheet.id}" and
                 item.action ==
                   %{
                     kind: "navigate",
                     url: "/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
                   }
             end)
    end

    test "rate limits consecutive submitted full searches without throttling scoped searches",
         %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project, %{name: "Cobalt Archive", shortcut: "cobalt-archive"})
      view = project_view(conn, workspace, project)

      render_hook(view, "palette_advanced_search", %{
        "query" => "*cobalt",
        "submitted" => true,
        "token" => 26
      })

      assert_reply(view, %{token: 26, mode: "all"})

      render_hook(view, "palette_advanced_search", %{
        "query" => "*cobalt",
        "submitted" => true,
        "token" => 27
      })

      assert_reply(view, %{token: 27, error: "rate_limited"})

      render_hook(view, "palette_advanced_search", %{
        "query" => "#cobalt",
        "submitted" => false,
        "token" => 28
      })

      assert_reply(view, %{token: 28, mode: "sheets", items: items})
      assert Enum.any?(items, &(&1.id == "sheet:#{sheet.id}"))
    end

    test "marks qualified references as fallback when a variable predicate has no matches",
         %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      kael = sheet_fixture(project, %{name: "Kael", shortcut: "kael"})
      nyx = sheet_fixture(project, %{name: "Nyx", shortcut: "nyx"})

      block_fixture(kael, %{
        type: "select",
        config: %{"label" => "Faction"},
        value: %{"content" => "spiritbound"}
      })

      block_fixture(nyx, %{
        type: "select",
        config: %{"label" => "Faction"},
        value: %{"content" => "independent"}
      })

      view = project_view(conn, workspace, project)

      render_hook(view, "palette_advanced_search", %{
        "query" => "$faction = conclave",
        "submitted" => false,
        "token" => 29
      })

      assert_reply(view, %{
        token: 29,
        mode: "variables",
        fallback: "qualified_references",
        items: items
      })

      assert Enum.map(items, & &1.label) == ["kael.faction", "nyx.faction"]

      assert Enum.all?(items, fn item ->
               item.group == "suggestion" and item.action.kind == "complete" and
                 String.ends_with?(item.action.value, " = conclave")
             end)
    end

    test "maps variable owners and active usages to validated deep links",
         %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 10}
        })

      condition = variable_condition(sheet.shortcut, block.variable_name)
      assignment = variable_assignment(sheet.shortcut, block.variable_name)

      flow = flow_fixture(project, %{name: "Health logic"})

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{"assignments" => [assignment]}
        })

      :ok = Storyarn.References.update_flow_node_variable_references(node)

      scene = scene_fixture(project, %{name: "Camp"})
      pin = pin_fixture(scene, %{"label" => "Gate", "condition" => condition})

      {:ok, _ambient_flow} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => flow.id,
          "trigger_type" => "on_event",
          "trigger_config" => %{"variable_ref" => "hero.#{block.variable_name}"}
        })

      zone =
        zone_fixture(scene, %{
          "name" => "Fountain",
          "action_type" => "action",
          "action_data" => %{"assignments" => [assignment]}
        })

      view = project_view(conn, workspace, project)

      render_hook(view, "palette_advanced_search", %{
        "query" => "$hero.#{block.variable_name}",
        "submitted" => false,
        "token" => 25
      })

      assert_reply(view, %{token: 25, mode: "variables", items: items})

      urls = MapSet.new(items, & &1.action.url)
      base = "/workspaces/#{workspace.slug}/projects/#{project.slug}"

      assert "#{base}/sheets/#{sheet.id}?highlight=block:#{block.id}" in urls
      assert "#{base}/flows/#{flow.id}?highlight=node:#{node.id}" in urls
      assert "#{base}/scenes/#{scene.id}" in urls
      assert "#{base}/scenes/#{scene.id}?highlight=pin:#{pin.id}" in urls
      assert "#{base}/scenes/#{scene.id}?highlight=zone:#{zone.id}" in urls
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

  describe "palette_operation_options" do
    test "goto.destination returns only authorized destinations", %{
      view: view,
      user: user
    } do
      workspace = workspace_fixture(user, %{name: "Visible destination workspace"})
      project = project_fixture(user, %{workspace: workspace, name: "Visible project"})
      sheet = sheet_fixture(project, %{name: "Visible destination"})

      other_user = user_fixture()
      other_workspace = workspace_fixture(other_user)
      other_project = project_fixture(other_user, %{workspace: other_workspace})
      hidden_sheet = sheet_fixture(other_project, %{name: "Visible destination leak"})

      render_hook(view, "palette_operation_options", %{
        "operation_id" => "goto",
        "parameter_id" => "destination",
        "query" => "Visible destination",
        "token" => 31
      })

      assert_reply(view, %{token: 31, items: items})

      assert Enum.any?(items, fn item ->
               item.id == "nav.sheet.#{sheet.id}" and
                 item.label == "Visible destination" and
                 item.value ==
                   "/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}" and
                 item.meta.type == "sheet"
             end)

      assert hd(items).id == "nav.workspace.#{workspace.id}"
      refute Enum.any?(items, &(&1.id == "nav.sheet.#{hidden_sheet.id}"))
    end

    test "delete.entity returns entities only from editable projects", %{
      view: view,
      user: user
    } do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      deletable_sheet = sheet_fixture(project, %{name: "Disposable sheet"})

      owner = user_fixture()
      viewer_workspace = workspace_fixture(owner)
      viewer_project = project_fixture(owner, %{workspace: viewer_workspace})
      hidden_sheet = sheet_fixture(viewer_project, %{name: "Disposable sheet hidden"})
      membership_fixture(viewer_project, user, "viewer")

      render_hook(view, "palette_operation_options", %{
        "operation_id" => "delete",
        "parameter_id" => "entity",
        "query" => "Disposable",
        "token" => 33
      })

      assert_reply(view, %{token: 33, items: items})

      assert Enum.any?(items, fn item ->
               item.id == "sheet:#{deletable_sheet.id}" and
                 item.value == %{
                   id: deletable_sheet.id,
                   type: "sheet",
                   projectId: project.id
                 }
             end)

      refute Enum.any?(items, &(&1.id == "sheet:#{hidden_sheet.id}"))
    end

    test "fails closed for unknown operation, parameter, or client-side completion source",
         %{view: view} do
      invalid_pairs = [
        {"forged", "destination"},
        {"goto", "forged"},
        {"create", "entity_type"},
        {"create", "project"},
        {"run_command", "command"},
        {"open_view", "destination"}
      ]

      for {{operation_id, parameter_id}, token} <- Enum.with_index(invalid_pairs, 34) do
        render_hook(view, "palette_operation_options", %{
          "operation_id" => operation_id,
          "parameter_id" => parameter_id,
          "query" => "",
          "token" => token
        })

        assert_reply(view, %{token: ^token, error: "invalid_request"})
      end
    end

    test "echoes the request token when a malformed options payload fails closed",
         %{view: view} do
      render_hook(view, "palette_operation_options", %{
        "operation_id" => "goto",
        "parameter_id" => "destination",
        "query" => String.duplicate("x", 401),
        "token" => 35
      })

      assert_reply(view, %{token: 35, error: "invalid_request"})
    end

    test "instant goto completion stays within its 150 ms budget at realistic size",
         %{view: view, user: user} do
      workspace = workspace_fixture(user, %{name: "Latency workspace"})

      # Stay within the free-plan project allowance while keeping the result
      # set large enough to exercise 144 project entities.
      for project_index <- 1..3 do
        project =
          project_fixture(user, %{
            workspace: workspace,
            name: "Latency project #{project_index}"
          })

        for entity_index <- 1..16 do
          sheet_fixture(project, %{name: "Latency sheet #{project_index}-#{entity_index}"})
          flow_fixture(project, %{name: "Latency flow #{project_index}-#{entity_index}"})
          scene_fixture(project, %{name: "Latency scene #{project_index}-#{entity_index}"})
        end
      end

      # Warm the query plan and sandbox connection before measuring the
      # interactive contract. The median rejects one scheduler hiccup while a
      # systematic regression still fails the hard budget.
      render_hook(view, "palette_operation_options", operation_options_payload(40))
      assert_reply(view, %{token: 40, items: [_first | _rest]})

      durations =
        for token <- 41..43 do
          {elapsed_microseconds, :ok} =
            :timer.tc(fn ->
              render_hook(view, "palette_operation_options", operation_options_payload(token))
              assert_reply(view, %{token: ^token, items: [_first | _rest]})
              :ok
            end)

          elapsed_microseconds
        end

      median_microseconds = durations |> Enum.sort() |> Enum.at(1)
      budget_microseconds = Definition.latency_budget_ms(:instant) * 1_000

      assert median_microseconds <= budget_microseconds,
             "median goto completion was #{median_microseconds / 1_000} ms, budget is #{budget_microseconds / 1_000} ms"
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
        "execution_id" => "create-sheet-1"
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
        "execution_id" => "create-localized-sheet"
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
          "execution_id" => "create-#{type}-1"
        })

        assert_reply(view, %{url: url})
        assert url =~ "/workspaces/#{workspace.slug}/projects/#{project.slug}/#{path}/"
        assert_receive {:tree_changed, ^tree_key}
      end
    end

    test "replaying an execution id returns the original result without creating twice",
         %{view: view, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      recipient = user_fixture()
      membership_fixture(project, recipient, "editor")
      recipient_scope = user_scope_fixture(recipient)
      :ok = Notifications.subscribe(recipient_scope)
      payload = %{"type" => "sheet", "project_id" => project.id, "execution_id" => "stable-create-id"}

      render_hook(view, "palette_create", payload)
      assert_reply(view, %{url: first_url})

      assert_receive :notifications_changed

      assert [notification] = Notifications.list_notifications(recipient_scope)
      assert notification.kind == "content_created"
      assert notification.entity_type == "sheet"
      assert notification.entity_name == "Untitled"

      render_hook(view, "palette_create", payload)
      assert_reply(view, %{url: second_url})

      assert first_url == second_url
      assert length(Storyarn.Sheets.search_sheets_in_projects([project.id], "")) == 1
      assert [replayed_notification] = Notifications.list_notifications(recipient_scope)
      assert replayed_notification.id == notification.id
      refute_receive :notifications_changed, 100
    end

    test "replaying after a LiveView reconnect returns the durable create result",
         %{view: view, user: user, conn: conn, workspace_path: workspace_path} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      payload = %{"type" => "sheet", "project_id" => project.id, "execution_id" => "reconnected-create-id"}

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
        "execution_id" => "unauthorized-create"
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
        "execution_id" => "delete-sheet-1"
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
        "execution_id" => "oversized-delete"
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
        "execution_id" => "readonly-delete"
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
        "execution_id" => "mismatched-delete"
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
          "execution_id" => "delete-#{type}-1"
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
        "execution_id" => "delete-referenced-flow"
      })

      assert_reply(view, %{deleted: true})

      assert_receive {:remote_change, :flow_refresh, %{user_id: 0, user_email: "System", user_color: "#666"}}
    end

    test "replaying after a LiveView reconnect returns the durable delete result",
         %{view: view, user: user, conn: conn, workspace_path: workspace_path} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(project)
      recipient = user_fixture()
      membership_fixture(project, recipient, "editor")
      recipient_scope = user_scope_fixture(recipient)
      :ok = Notifications.subscribe(recipient_scope)

      payload = %{
        "type" => "sheet",
        "id" => sheet.id,
        "project_id" => project.id,
        "execution_id" => "reconnected-delete-id"
      }

      render_hook(view, "palette_delete", payload)
      assert_reply(view, %{deleted: true})

      assert_receive :notifications_changed

      assert [notification] = Notifications.list_notifications(recipient_scope)
      assert notification.kind == "content_deleted"
      assert notification.entity_type == "sheet"
      assert notification.entity_id == sheet.id
      assert notification.entity_name == sheet.name

      {:ok, reconnected_view, _html} = live(conn, workspace_path)
      render_hook(reconnected_view, "palette_delete", payload)
      assert_reply(reconnected_view, %{deleted: true})

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id) == nil
      assert [replayed_notification] = Notifications.list_notifications(recipient_scope)
      assert replayed_notification.id == notification.id
      refute_receive :notifications_changed, 100
    end
  end

  test "malformed known palette events fail closed without reaching the host LiveView", %{view: view} do
    invalid_events = [
      {"palette_operation_options",
       %{
         "operation_id" => "goto",
         "parameter_id" => "destination",
         "query" => "",
         "token" => "bad"
       }},
      {"palette_advanced_search", %{"query" => "#kael", "submitted" => false, "token" => "bad"}},
      {"palette_nav", %{"query" => "test", "token" => "bad"}},
      {"palette_create_targets", %{"token" => "bad"}},
      {"palette_create", %{"type" => "sheet", "project_id" => 1}},
      {"palette_delete_search", %{"query" => 123, "token" => 1}},
      {"palette_delete", %{"type" => "sheet", "id" => 1, "project_id" => 1}},
      {"palette_opened", %{"surface" => "forged"}},
      {"palette_command_executed", %{"command_id" => 123, "surface" => "workspace"}},
      {"palette_search_no_results", %{"query_length" => -1, "surface" => "workspace"}},
      {"palette_operation_selected", %{"operation_id" => 123, "surface" => "workspace"}},
      {"palette_operation_completed", %{"operation_id" => "goto", "surface" => "forged"}},
      {"palette_operation_completed", %{"operation_id" => String.duplicate("x", 65), "surface" => "workspace"}},
      {"palette_operation_abandoned", %{"surface" => "workspace"}}
    ]

    for {event, payload} <- invalid_events do
      render_hook(view, event, payload)
      assert_reply(view, %{error: "invalid_request"})
    end
  end

  defp operation_options_payload(token) do
    %{
      "operation_id" => "goto",
      "parameter_id" => "destination",
      "query" => "Latency",
      "token" => token
    }
  end

  defp project_view(conn, workspace, project) do
    {:ok, view, _html} =
      live(conn, ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}")

    view
  end

  defp variable_condition(sheet_shortcut, variable_name) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }
  end

  defp variable_assignment(sheet_shortcut, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value" => "11",
      "value_type" => "literal"
    }
  end
end
