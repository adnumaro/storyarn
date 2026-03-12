defmodule Storyarn.Versioning.AutoSnapshotTest do
  @moduledoc "Tests that facade maybe_create_version defaults is_auto: true."
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.EntityVersion

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "Sheets.maybe_create_version/3 defaults is_auto: true" do
    test "auto-snapshot has is_auto flag set", %{user: user, project: project} do
      sheet = sheet_fixture(project)
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      sheet = Storyarn.Repo.preload(sheet, :blocks, force: true)

      {:ok, version} = Storyarn.Sheets.maybe_create_version(sheet, user.id)
      assert %EntityVersion{is_auto: true} = version
    end

    test "explicit is_auto: false overrides default", %{user: user, project: project} do
      sheet = sheet_fixture(project)
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      sheet = Storyarn.Repo.preload(sheet, :blocks, force: true)

      {:ok, version} = Storyarn.Sheets.maybe_create_version(sheet, user.id, is_auto: false)
      assert %EntityVersion{is_auto: false} = version
    end
  end

  describe "Flows.maybe_create_version/3 defaults is_auto: true" do
    test "auto-snapshot has is_auto flag set", %{user: user, project: project} do
      flow = flow_fixture(project)
      flow = Storyarn.Repo.preload(flow, [:nodes, :connections], force: true)

      {:ok, version} = Storyarn.Flows.maybe_create_version(flow, user.id)
      assert %EntityVersion{is_auto: true} = version
    end
  end

  describe "Scenes.maybe_create_version/3 defaults is_auto: true" do
    test "auto-snapshot has is_auto flag set", %{user: user, project: project} do
      scene = scene_fixture(project)

      scene =
        Storyarn.Repo.preload(scene, [:layers, :zones, :pins, :connections, :annotations],
          force: true
        )

      {:ok, version} = Storyarn.Scenes.maybe_create_version(scene, user.id)
      assert %EntityVersion{is_auto: true} = version
    end
  end

  describe "rate limiting" do
    test "second call within window is skipped", %{user: user, project: project} do
      flow = flow_fixture(project)
      flow = Storyarn.Repo.preload(flow, [:nodes, :connections], force: true)

      {:ok, _v1} = Storyarn.Flows.maybe_create_version(flow, user.id)
      assert {:skipped, :too_recent} = Storyarn.Flows.maybe_create_version(flow, user.id)
    end
  end
end
