defmodule StoryarnWeb.ProjectSettingsLive.TrashTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  defp get_trash_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsTrash")
  end

  defp get_settings_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  describe "Trash page" do
    setup :register_and_log_in_user

    test "renders Trash Vue component for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      settings = get_settings_layout_vue(view)

      assert settings.props["current-path"] ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"

      assert settings.props["project"]["slug"] == project.slug

      vue = get_trash_vue(view)
      assert vue.component == "live/project/settings/ProjectSettingsTrash"
      assert vue.props["can-manage"] == true
      assert vue.props["pagination"]["page"] == 1
    end

    test "renders for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      assert vue.component == "live/project/settings/ProjectSettingsTrash"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "passes empty list when trash is empty", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      assert vue.props["trashed-items"] == []
    end

    test "survives replacement invalidations and reloads recoverable trash after a project snapshot restore", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Displaced by restore"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      assert get_trash_vue(view).props["trashed-items"] == []
      {:ok, _trashed} = Sheets.delete_sheet(sheet)

      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "project:#{project.id}:shell",
        {:entities_deleted, :sheet, [sheet.id]}
      )

      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "project:#{project.id}:shell",
        {:project_restored, 42}
      )

      _html = render(view)

      assert Enum.any?(
               get_trash_vue(view).props["trashed-items"],
               &match?(%{"type" => "sheet", "name" => "Displaced by restore"}, &1)
             )
    end

    test "ignores collaborator sidebar messages on the shared shell topic", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "project:#{project.id}:shell",
        {:tree_changed, :flows}
      )

      _html = render(view)
      assert get_trash_vue(view).props["trashed-items"] == []
    end

    test "passes all project trash item types to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Deleted Sheet"})
      flow = flow_fixture(project, %{name: "Deleted Flow"})
      scene = scene_fixture(project, %{name: "Deleted Scene"})
      asset = image_asset_fixture(project, user, %{filename: "Deleted Asset.png", size: 2_048})

      {:ok, _} = Sheets.delete_sheet(sheet)
      {:ok, _} = Flows.delete_flow(flow)
      {:ok, _} = Scenes.delete_scene(scene)
      {:ok, trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      items = vue.props["trashed-items"]

      assert Enum.any?(items, &match?(%{"type" => "sheet", "name" => "Deleted Sheet"}, &1))
      assert Enum.any?(items, &match?(%{"type" => "flow", "name" => "Deleted Flow"}, &1))
      assert Enum.any?(items, &match?(%{"type" => "scene", "name" => "Deleted Scene"}, &1))

      assert Enum.any?(items, fn item ->
               item["type"] == "asset" and
                 item["name"] == "Deleted Asset.png" and
                 item["content_type"] == "image/png" and
                 item["size"] == 2_048 and
                 item["deletion_reason"] == "user" and
                 item["deletion_generation"] == trashed_asset.deletion_generation and
                 is_binary(item["purge_at"])
             end)

      refute Enum.any?(items, &Map.has_key?(&1, "deleted_by_id"))

      assert vue.props["pagination"]["totalCount"] == 4
      assert vue.props["type-counts"] == %{"asset" => 1, "flow" => 1, "scene" => 1, "sheet" => 1}
    end

    test "paginates project trash items", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      for index <- 1..26 do
        sheet = sheet_fixture(project, %{name: "Deleted Sheet #{index}"})
        {:ok, _} = Sheets.delete_sheet(sheet)
      end

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      assert length(vue.props["trashed-items"]) == 25
      assert vue.props["pagination"]["totalCount"] == 26
      assert vue.props["pagination"]["totalPages"] == 2

      render_hook(view, "change_trash_page", %{"page" => 2})

      vue = get_trash_vue(view)
      assert vue.props["pagination"]["page"] == 2
      assert length(vue.props["trashed-items"]) == 1
    end

    test "filters project trash items in the backend", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Deleted Sheet"})
      flow = flow_fixture(project, %{name: "Deleted Flow"})

      {:ok, _} = Sheets.delete_sheet(sheet)
      {:ok, _} = Flows.delete_flow(flow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "set_trash_filter", %{"type" => "flow"})

      vue = get_trash_vue(view)
      assert [%{"type" => "flow", "name" => "Deleted Flow"}] = vue.props["trashed-items"]
      assert vue.props["pagination"]["totalCount"] == 1

      render_hook(view, "search_trash", %{"query" => "Sheet"})

      vue = get_trash_vue(view)
      assert vue.props["trashed-items"] == []
      assert vue.props["pagination"]["totalCount"] == 0
    end

    test "restores trashed item by type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Restorable Flow"})
      {:ok, _} = Flows.delete_flow(flow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "restore_item", %{"type" => "flow", "id" => flow.id})

      assert Flows.get_flow(project.id, flow.id)
      refute Enum.any?(get_trash_vue(view).props["trashed-items"], &(&1["id"] == flow.id and &1["type"] == "flow"))
    end

    test "suggests restoring a trashed dependency when a reference is unavailable", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      source = sheet_fixture(project, %{name: "Source"})
      target = sheet_fixture(project, %{name: "Target"})

      block_fixture(source, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target.id}
      })

      {:ok, _source} = Sheets.delete_sheet(source)
      {:ok, _target} = Sheets.delete_sheet(target)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      html = render_hook(view, "restore_item", %{"type" => "sheet", "id" => source.id})

      assert html =~ "If any referenced items are in Trash, restore them first and try again"
      assert %Sheet{deleted_at: %DateTime{}} = Repo.get!(Sheet, source.id)
    end

    test "suggests restoring a trashed parent before restoring a flow", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      parent = flow_fixture(project, %{name: "Parent"})
      child = flow_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, _child} = Flows.delete_flow(child)
      {:ok, _parent} = Flows.delete_flow(parent)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      html = render_hook(view, "restore_item", %{"type" => "flow", "id" => child.id})

      assert html =~ "If any referenced items are in Trash, restore them first and try again"
      assert %DateTime{} = Flows.get_flow_including_deleted(project.id, child.id).deleted_at
    end

    test "suggests restoring a trashed scene before restoring its flow", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Map"})
      flow = flow_fixture(project, %{name: "Scene flow", scene_id: scene.id})

      {:ok, _flow} = Flows.delete_flow(flow)
      {:ok, _scene} = Scenes.delete_scene(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      html = render_hook(view, "restore_item", %{"type" => "flow", "id" => flow.id})

      assert html =~ "If any referenced items are in Trash, restore them first and try again"
      assert %DateTime{} = Flows.get_flow_including_deleted(project.id, flow.id).deleted_at
    end

    test "permanently deletes trashed item by type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Disposable Scene"})
      {:ok, _} = Scenes.delete_scene(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "delete_item", %{"type" => "scene", "id" => scene.id})

      assert Scenes.get_scene_including_deleted(project.id, scene.id) == nil
    end

    test "filters, restores, and permanently deletes assets with their deletion generation", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      restorable = image_asset_fixture(project, user, %{filename: "Restorable Asset.png"})
      disposable = image_asset_fixture(project, user, %{filename: "Disposable Asset.png"})

      {:ok, restorable} = Assets.move_asset_to_trash(project.id, restorable.id, user.id)
      {:ok, disposable} = Assets.move_asset_to_trash(project.id, disposable.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "set_trash_filter", %{"type" => "asset"})
      assert Enum.all?(get_trash_vue(view).props["trashed-items"], &(&1["type"] == "asset"))

      render_hook(view, "restore_item", %{
        "type" => "asset",
        "id" => restorable.id,
        "generation" => restorable.deletion_generation
      })

      assert %Asset{deleted_at: nil} = Repo.get!(Asset, restorable.id)

      render_hook(view, "delete_item", %{
        "type" => "asset",
        "id" => disposable.id,
        "generation" => disposable.deletion_generation
      })

      assert Repo.get(Asset, disposable.id) == nil
    end

    test "restoring an asset notifies other open asset views", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{filename: "Shared Asset.png"})
      {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)
      :ok = Storyarn.Platform.Collaboration.subscribe_changes({:assets, project.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "restore_item", %{
        "type" => "asset",
        "id" => asset.id,
        "generation" => trashed.deletion_generation
      })

      assert_receive {:remote_change, :asset_restored, %{}}, 1_000
    end

    test "explains why a referenced asset cannot be permanently deleted", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{filename: "Referenced Asset.png"})
      sheet = sheet_fixture(project, %{name: "Recoverable Sheet", banner_asset_id: asset.id})

      {:ok, _trashed_sheet} = Sheets.delete_sheet(sheet)
      {:ok, trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      html =
        render_hook(view, "delete_item", %{
          "type" => "asset",
          "id" => asset.id,
          "generation" => trashed_asset.deletion_generation
        })

      assert html =~ "Remove those references or permanently delete the referencing items from Trash"
      assert %Asset{deleted_at: %DateTime{}} = Repo.get!(Asset, asset.id)
      assert %Sheet{deleted_at: %DateTime{}} = Repo.get!(Sheet, sheet.id)
    end

    test "rejects stale asset generations without mutating the trashed row", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user)
      {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      html =
        render_hook(view, "restore_item", %{
          "type" => "asset",
          "id" => asset.id,
          "generation" => trashed.deletion_generation + 1
        })

      assert html =~ "Failed to restore item"
      assert %Asset{deleted_at: %DateTime{}} = Repo.get!(Asset, asset.id)
    end

    test "empty trash treats asset family members purged by an earlier member as already removed", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      original = image_asset_fixture(project, user, %{filename: "Portrait.png"})
      variant = image_asset_fixture(project, user, %{filename: "Portrait.webp"})

      {:ok, _original} =
        Assets.update_asset(original, %{
          metadata: %{"web_asset_id" => variant.id, "web_url" => variant.url}
        })

      {:ok, _variant} =
        Assets.update_asset(variant, %{
          metadata: %{"is_variant" => true, "original_asset_id" => original.id}
        })

      {:ok, _trashed} = Assets.move_asset_to_trash(project.id, original.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      assert get_trash_vue(view).props["pagination"]["totalCount"] == 2
      assert render_hook(view, "empty_trash", %{}) =~ "Trash emptied successfully"
      assert Repo.get(Asset, original.id) == nil
      assert Repo.get(Asset, variant.id) == nil
    end

    test "empty trash removes trashed entity owners before their asset references", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{filename: "Former Banner.png"})
      sheet = sheet_fixture(project, %{banner_asset_id: asset.id})

      assert {:ok, _sheet} = Sheets.delete_sheet(sheet)
      assert {:ok, _asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      assert get_trash_vue(view).props["pagination"]["totalCount"] == 2
      assert render_hook(view, "empty_trash", %{}) =~ "Trash emptied successfully"
      assert Repo.get(Sheet, sheet.id) == nil
      assert Repo.get(Asset, asset.id) == nil
    end

    test "viewer cannot forge asset restore, purge, or empty-trash events", %{conn: conn, user: viewer} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      membership_fixture(project, viewer, "viewer")
      asset = image_asset_fixture(project, owner)
      {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, owner.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      assert get_trash_vue(view).props["can-manage"] == false

      for event <- ["restore_item", "delete_item"] do
        html =
          render_hook(view, event, %{
            "type" => "asset",
            "id" => asset.id,
            "generation" => trashed.deletion_generation
          })

        assert html =~ "permission"
      end

      assert render_hook(view, "empty_trash", %{}) =~ "permission"
      assert %Asset{deleted_at: %DateTime{}} = Repo.get!(Asset, asset.id)
    end

    test "cannot restore or purge an asset from another project through the route", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      other_project = user |> project_fixture() |> Repo.preload(:workspace)
      foreign_asset = image_asset_fixture(other_project, user)
      {:ok, trashed} = Assets.move_asset_to_trash(other_project.id, foreign_asset.id, user.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      for event <- ["restore_item", "delete_item"] do
        render_hook(view, event, %{
          "type" => "asset",
          "id" => foreign_asset.id,
          "generation" => trashed.deletion_generation
        })
      end

      assert %Asset{deleted_at: %DateTime{}} = Repo.get!(Asset, foreign_asset.id)
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/settings/trash")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
