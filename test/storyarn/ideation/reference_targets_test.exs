defmodule Storyarn.Ideation.ReferenceTargetsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Ideation.References.Queries.Targets
  alias Storyarn.Localization
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  setup do
    owner = user_fixture()
    project = project_fixture(owner)
    viewer = user_fixture()
    membership_fixture(project, viewer, "viewer")

    %{
      owner: owner,
      scope: user_scope_fixture(owner),
      viewer: user_scope_fixture(viewer),
      outsider: user_scope_fixture(),
      project: project
    }
  end

  test "all five owners expose project-authorized target queries", ctx do
    for owner <- [Sheets, Flows, Scenes, Projects, Localization] do
      assert {:ok, %Ecto.Query{}} = owner.reference_targets_query(ctx.scope, ctx.project.id)
      assert {:ok, %Ecto.Query{}} = owner.reference_targets_query(ctx.viewer, ctx.project.id)
      assert {:error, :not_found} = owner.reference_targets_query(ctx.outsider, ctx.project.id)

      for scope <- [nil, %{}, %{user: nil}] do
        assert {:error, :not_found} = owner.reference_targets_query(scope, ctx.project.id)
      end
    end
  end

  test "batch projections identify existing targets without exposing asset locations", ctx do
    sheet = sheet_fixture(ctx.project, %{name: "Character", description: "<p>Initial premise</p>"})
    flow = flow_fixture(ctx.project, %{name: "Opening"})
    scene = scene_fixture(ctx.project, %{name: "Village"})
    asset = asset_fixture(ctx.project, ctx.owner)
    localized = localized_text_fixture(ctx.project.id, %{source_text: "Welcome", translated_text: "Bienvenido"})

    entities = [
      {"sheet", sheet},
      {"flow", flow},
      {"scene", scene},
      {"asset", asset},
      {"localization", localized}
    ]

    keys = Enum.map(entities, fn {type, entity} -> {type, entity.id} end)

    assert {:ok, targets} = Targets.get_many(ctx.viewer, ctx.project.id, keys)
    assert map_size(targets) == 5

    for {type, entity} <- entities do
      target = targets[{type, entity.id}]
      assert target.type == type
      assert target.id == entity.id
      assert target.context["comparison_scope"] == "overview_v1"
      assert target.identity == "created:" <> DateTime.to_iso8601(entity.inserted_at)
      assert byte_size(target.fingerprint) == 64
      assert {:ok, ^target} = Targets.get(ctx.viewer, ctx.project.id, type, entity.id)
      assert {:ok, results} = Targets.search(ctx.viewer, ctx.project.id, type, "")
      assert Enum.find(results, &(&1.id == entity.id)) == target
    end

    assert targets[{"sheet", sheet.id}].context["description"] == "Initial premise"
    assert targets[{"localization", localized.id}].locator.locale_code == "es"
    assert targets[{"localization", localized.id}].context["translated_text"] == "Bienvenido"
    refute inspect(targets) =~ asset.key
    refute inspect(targets) =~ asset.url
    assert {:error, :not_found} = Targets.get_many(ctx.outsider, ctx.project.id, keys)
  end

  test "targets from other projects, deleted content and archived localized rows are unavailable", ctx do
    other_project = project_fixture(ctx.owner)
    other_sheet = sheet_fixture(other_project)
    sheet = sheet_fixture(ctx.project)
    flow = flow_fixture(ctx.project)
    scene = scene_fixture(ctx.project)
    asset = asset_fixture(ctx.project, ctx.owner)
    localized = localized_text_fixture(ctx.project.id)

    for {type, entity} <- [{"sheet", sheet}, {"flow", flow}, {"scene", scene}] do
      entity |> change(deleted_at: TimeHelpers.now()) |> Repo.update!()
      assert {:error, :not_found} = Targets.get(ctx.scope, ctx.project.id, type, entity.id)
      assert {:ok, []} = Targets.search(ctx.scope, ctx.project.id, type, "")
    end

    assert {:ok, _trashed} = Projects.move_asset_to_trash(ctx.project.id, asset.id, ctx.owner.id)
    assert {:error, :not_found} = Targets.get(ctx.scope, ctx.project.id, "asset", asset.id)
    assert {:ok, []} = Targets.search(ctx.scope, ctx.project.id, "asset", "")

    localized |> change(archived_at: TimeHelpers.now(), archive_reason: "source_deleted") |> Repo.update!()
    assert {:error, :not_found} = Targets.get(ctx.scope, ctx.project.id, "localization", localized.id)
    assert {:ok, []} = Targets.search(ctx.scope, ctx.project.id, "localization", "")
    assert {:error, :not_found} = Targets.get(ctx.scope, ctx.project.id, "sheet", other_sheet.id)
  end

  test "search escapes wildcard input and bounds result pages", ctx do
    matching = sheet_fixture(ctx.project, %{name: "100% certainty", shortcut: "certainty"})
    sheet_fixture(ctx.project, %{name: "100 percent", shortcut: "percent"})

    assert {:ok, [target]} = Targets.search(ctx.scope, ctx.project.id, "sheet", "%")
    assert target.id == matching.id
    assert {:ok, [same]} = Targets.search(ctx.scope, ctx.project.id, "sheet", "certainty")
    assert same.id == matching.id
    assert {:ok, [_target]} = Targets.search(ctx.scope, ctx.project.id, "sheet", "", limit: 1)
    assert {:ok, [_target]} = Targets.search(ctx.scope, ctx.project.id, "sheet", "", limit: 1, offset: 1)
    assert {:error, :not_found} = Targets.search(ctx.scope, ctx.project.id, "sheet", String.duplicate("x", 501))
  end

  test "context is bounded in bytes and detects metadata changes beyond its excerpt", ctx do
    prefix = String.duplicate("é", 1_200)
    sheet = sheet_fixture(ctx.project, %{description: prefix <> " first"})

    assert {:ok, original} = Targets.get(ctx.scope, ctx.project.id, "sheet", sheet.id)
    assert byte_size(original.context["description"]) <= 2_000
    assert String.valid?(original.context["description"])
    assert original.context["description_truncated"]

    sheet |> change(description: prefix <> " second") |> Repo.update!()
    assert {:ok, changed} = Targets.get(ctx.scope, ctx.project.id, "sheet", sheet.id)
    assert changed.context == original.context
    refute changed.fingerprint == original.fingerprint
    assert changed.identity == original.identity
  end

  test "the overview comparison is not a content snapshot or a whole-aggregate detector", ctx do
    sheet = sheet_fixture(ctx.project)
    assert {:ok, original} = Targets.get(ctx.scope, ctx.project.id, "sheet", sheet.id)
    block_fixture(sheet, %{value: %{"content" => "New authored field"}})
    assert {:ok, changed} = Targets.get(ctx.scope, ctx.project.id, "sheet", sheet.id)
    assert changed.fingerprint == original.fingerprint
    refute inspect(changed.context) =~ "New authored field"
  end

  test "malformed selection never becomes a foreign or unbounded database lookup", ctx do
    for {type, id} <- [
          {"unknown", 1},
          {"sheet", nil},
          {"sheet", "1"},
          {"sheet", 0},
          {"sheet", 9_223_372_036_854_775_808}
        ] do
      assert {:error, :not_found} = Targets.get(ctx.scope, ctx.project.id, type, id)
    end

    assert {:error, :not_found} = Targets.search(ctx.scope, ctx.project.id, "sheet", "", [:invalid])
    assert {:error, :not_found} = Targets.get(nil, ctx.project.id, "sheet", 1)
    assert {:error, :not_found} = Targets.get_many(ctx.scope, ctx.project.id, [%{type: "sheet", id: 1}])
  end

  test "batch query count does not grow with the number of targets", ctx do
    stamp = TimeHelpers.now()

    rows =
      Enum.map(1..30, fn number ->
        %{
          project_id: ctx.project.id,
          name: "Target #{number}",
          inserted_at: stamp,
          updated_at: stamp
        }
      end)

    {30, ids} = Repo.insert_all(Sheets.Sheet, rows, returning: [:id])
    keys = Enum.map(ids, &{"sheet", &1.id})
    {single, one_count} = count_queries(fn -> Targets.get_many(ctx.scope, ctx.project.id, Enum.take(keys, 1)) end)
    {many, many_count} = count_queries(fn -> Targets.get_many(ctx.scope, ctx.project.id, keys) end)
    assert map_size(single) == 1
    assert map_size(many) == 30
    assert one_count == many_count
    assert many_count <= 10
    assert {:ok, first_page} = Targets.search(ctx.scope, ctx.project.id, "sheet", "")
    assert length(first_page) == 20
    assert {:error, :not_found} = Targets.get_many(ctx.scope, ctx.project.id, List.duplicate(hd(keys), 51))
  end

  test "membership revoked during materialization prevents returning the captured target", ctx do
    sheet = sheet_fixture(ctx.project)
    marker = make_ref()
    Process.put(marker, true)

    :ok =
      :telemetry.attach(
        marker,
        [:storyarn, :repo, :query],
        &revoke_during_read/4,
        {self(), marker, ctx.project.id, ctx.viewer.user.id}
      )

    try do
      assert {:error, :not_found} = Targets.get(ctx.viewer, ctx.project.id, "sheet", sheet.id)
      refute Process.get(marker), "access must be revoked during the target read"
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp count_queries(callback) do
    marker = make_ref()
    Process.put(marker, 0)
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &count_query/4, {self(), marker})

    try do
      assert {:ok, result} = callback.()
      {result, Process.get(marker)}
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp count_query(_event, _measurements, _metadata, {pid, marker}) do
    if self() == pid, do: Process.put(marker, Process.get(marker) + 1)
  end

  defp revoke_during_read(_event, _measurements, %{query: query}, {pid, marker, project_id, user_id}) do
    if self() == pid and String.contains?(query, ~s(FROM "sheets")) and Process.delete(marker) do
      Repo.delete_all(
        from(member in ProjectMembership, where: member.project_id == ^project_id and member.user_id == ^user_id)
      )
    end
  end
end
