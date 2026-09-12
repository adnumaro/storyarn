defmodule StoryarnWeb.ContextualSourceHeaderDiffTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    previous = Application.fetch_env!(:live_vue, :enable_props_diff)
    Application.put_env(:live_vue, :enable_props_diff, true)
    on_exit(fn -> Application.put_env(:live_vue, :enable_props_diff, previous) end)
    %{project: user |> project_fixture() |> Repo.preload(:workspace)}
  end

  test "a Flow save-status reset patches only the status, retaining health and scene props", ctx do
    scene_fixture(ctx.project, %{name: "Available scene"})
    flow = flow_fixture(ctx.project, %{name: "Original flow"})

    {:ok, view, _} =
      live(ctx.conn, ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/flows/#{flow.id}")

    await_async(view)
    assert header(view).use_diff
    assert [_ | _] = :sys.get_state(view.pid).socket.assigns.available_scenes

    render_hook(view, "save_name", %{name: "Renamed flow"})
    await_async(view)
    token = :sys.get_state(view.pid).socket.assigns.save_status_reset_token
    assert is_reference(token)
    send(view.pid, {:reset_save_status, token})

    assert header(view).props_diff == [["replace", "/save-status", "idle"]]
  end

  test "Sheet comment controls do not resend health", ctx do
    sheet = sheet_fixture(ctx.project, %{name: "Reviewable sheet"})

    {:ok, view, _} =
      live(ctx.conn, ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/sheets/#{sheet.id}")

    await_async(view)
    assert header(view).use_diff
    render_hook(view, "comments_mode", %{active: true})
    patches = header(view).props_diff

    assert [_ | _] = patches
    assert Enum.all?(patches, fn [_, path | _] -> path == "/comments" or String.starts_with?(path, "/comments/") end)
  end

  defp header(view), do: LiveVue.Test.get_vue(view, name: "live/shared/ContextualSourceHeader")
end
