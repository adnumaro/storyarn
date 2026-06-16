defmodule Storyarn.AnalyticsInstrumentationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets
  alias Storyarn.Projects
  alias Storyarn.Workspaces

  defmodule TestAdapter do
    @moduledoc false
    def capture(payload) do
      send(Process.get(:analytics_test_pid), {:analytics_capture, payload})
      :ok
    end

    def identify(payload) do
      send(Process.get(:analytics_test_pid), {:analytics_identify, payload})
      :ok
    end
  end

  setup do
    user = insert(:user)
    scope = Scope.for_user(user)
    original_adapter = Application.get_env(:storyarn, :analytics_adapter)

    Process.put(:analytics_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAdapter)

    on_exit(fn ->
      restore_env(:analytics_adapter, original_adapter)
      Process.delete(:analytics_test_pid)
    end)

    {:ok, scope: scope, user: user}
  end

  test "workspace creation emits a coarse analytics event", %{scope: scope} do
    distinct_id = "user:#{scope.user.id}"

    assert {:ok, workspace} =
             Workspaces.create_workspace(scope, %{
               name: "Analytics Workspace",
               slug: unique_slug("analytics-workspace")
             })

    workspace_id = workspace.id

    assert_receive {:analytics_capture,
                    %{
                      event: "workspace created",
                      distinct_id: ^distinct_id,
                      properties: %{"workspace_id" => ^workspace_id}
                    }}
  end

  test "project creation emits workspace and project ids", %{scope: scope} do
    distinct_id = "user:#{scope.user.id}"
    workspace = create_workspace!(scope)
    drain_analytics()

    assert {:ok, project} =
             Projects.create_project(scope, %{
               name: "Analytics Project",
               slug: unique_slug("analytics-project"),
               workspace_id: workspace.id,
               project_type: "game",
               project_subtype: "rpg"
             })

    project_id = project.id
    workspace_id = workspace.id

    assert_receive {:analytics_capture,
                    %{
                      event: "project created",
                      distinct_id: ^distinct_id,
                      properties: %{
                        "project_id" => ^project_id,
                        "workspace_id" => ^workspace_id,
                        "project_type" => "game",
                        "project_subtype" => "rpg"
                      }
                    }}
  end

  test "asset creation emits coarse file metadata", %{scope: scope, user: user} do
    distinct_id = "user:#{user.id}"
    workspace = create_workspace!(scope)
    project = create_project!(scope, workspace)
    drain_analytics()

    assert {:ok, _asset} =
             Assets.create_asset(project, user, %{
               filename: "private-filename.png",
               content_type: "image/png",
               size: 250_000,
               key: "test/#{unique_slug("asset")}.png",
               url: "/uploads/private-filename.png",
               metadata: %{"is_variant" => true}
             })

    project_id = project.id

    assert_receive {:analytics_capture,
                    %{
                      event: "asset uploaded",
                      distinct_id: ^distinct_id,
                      properties: %{
                        "asset_type" => "image",
                        "content_type" => "image/png",
                        "created_variant" => true,
                        "project_id" => ^project_id,
                        "size_bucket" => "100kb_to_1mb"
                      }
                    }}
  end

  defp create_workspace!(scope) do
    {:ok, workspace} =
      Workspaces.create_workspace(scope, %{
        name: "Analytics Workspace",
        slug: unique_slug("analytics-workspace")
      })

    workspace
  end

  defp create_project!(scope, workspace) do
    {:ok, project} =
      Projects.create_project(scope, %{
        name: "Analytics Project",
        slug: unique_slug("analytics-project"),
        workspace_id: workspace.id,
        project_type: "game",
        project_subtype: "rpg"
      })

    project
  end

  defp drain_analytics do
    receive do
      {:analytics_capture, _payload} -> drain_analytics()
      {:analytics_identify, _payload} -> drain_analytics()
    after
      0 -> :ok
    end
  end

  defp unique_slug(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp restore_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_env(key, value), do: Application.put_env(:storyarn, key, value)
end
