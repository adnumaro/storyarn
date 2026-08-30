defmodule Storyarn.Architecture.CommercialFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Commercial

  @public_contract [
    acquire_project_snapshot_export_lease: 1,
    active_project_snapshot_reservations: 1,
    can_accept_member?: 2,
    can_create_project?: 1,
    can_create_project_template?: 1,
    can_create_project_template_version?: 1,
    can_create_workspace?: 1,
    can_receive_workspace?: 1,
    can_invite_member?: 2,
    can_publish_reserved_project?: 1,
    can_upload_asset?: 2,
    can_upload_asset_for_project?: 2,
    commit_project_snapshot_restore_storage_reservation: 6,
    commit_project_storage_reservation: 5,
    create_subscription: 1,
    entitlement_limit: 2,
    extend_project_storage_reservation: 4,
    mark_project_storage_reservation_started: 4,
    plan_retention_hours: 1,
    plans_for_workspace_ids: 1,
    project_limits_usage: 1,
    project_snapshot_slot_usage: 1,
    project_storage_reservation_object_prefixes: 1,
    project_usage: 2,
    purge_released_snapshot_export_leases: 1,
    purge_released_snapshot_export_leases: 2,
    recover_expired_snapshot_export_leases: 1,
    recover_expired_snapshot_export_leases: 2,
    release_project_storage_reservation: 4,
    renew_project_storage_reservation: 3,
    reserve_project_storage: 1,
    settle_expired_snapshot_export_leases_locked: 2,
    snapshot_build_heartbeat_interval_ms: 0,
    snapshot_build_lease_ttl_seconds: 0,
    snapshot_download_export_lease_ttl_seconds: 0,
    snapshot_download_max_transfer_seconds: 0,
    snapshot_download_signed_url_ttl_seconds: 0,
    snapshot_export_lease_retention_seconds: 0,
    snapshot_storage_commit_context?: 2,
    subscribe_project_snapshot_export_leases: 1,
    transact_with_workspace_lock: 2,
    transact_with_workspace_lock: 3,
    with_storage_accounting_lock: 2,
    with_storage_accounting_lock: 3,
    workspace_lock_held?: 1,
    workspace_storage_usage: 1
  ]

  @public_types ~w(
    subscription_creation_error
    subscription_receipt
    storage_reservation_receipt
    storage_reservation_write_error
  )a
  @docs_digest "e7aeeef205178335bf36e2d98cb92e0f4a711ddec60206049ea15a459ab76cec"
  @types_digest "8989f40a036ba7d95841b2bd8b40e1f36b24504f12c8401f2f334488d90cb79f"
  @specs_digest "cd323b18d9e8bd87d0039c4e67b23f9f13f20f8764703c7cae0c230d66e8d4e1"

  test "the root facade exposes the complete extracted commercial contract" do
    public_functions =
      :functions
      |> Commercial.__info__()
      |> Enum.reject(fn {name, _arity} -> name in [:module_info, :__info__] end)
      |> MapSet.new()

    assert public_functions == MapSet.new(@public_contract)
  end

  test "the root facade remains declarative and composes only stable commercial facets" do
    source = File.read!("lib/storyarn/commercial.ex")

    refute Regex.match?(~r/^\s*def(?:p|macro|macrop)?\s/m, source)
    assert Regex.scan(~r/^\s*defdelegate\s/m, source) != []
    refute source =~ "Storyarn.Repo"
    refute source =~ "Storyarn.Platform"

    ast = Code.string_to_quoted!(source, file: "lib/storyarn/commercial.ex")

    {_ast, dependencies} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:__aliases__, _meta, [:Storyarn, :Commercial, _facet | _rest] = segments} = node, dependencies ->
          {node, MapSet.put(dependencies, Enum.join(segments, "."))}

        node, dependencies ->
          {node, dependencies}
      end)

    assert dependencies ==
             MapSet.new([
               "Storyarn.Commercial.Billing",
               "Storyarn.Commercial.Entitlements",
               "Storyarn.Commercial.ProjectStorageReservations"
             ])
  end

  test "the extracted facade owns its neutral cross-context result types" do
    assert {:ok, types} = Code.Typespec.fetch_types(Commercial)

    type_names =
      types
      |> Enum.map(fn {_kind, {name, _definition, _args}} -> name end)
      |> Enum.sort()

    normalized_types =
      types
      |> Enum.map(fn {kind, type} ->
        {kind, type |> Code.Typespec.type_to_quoted() |> Macro.to_string()}
      end)
      |> Enum.sort()

    assert type_names == Enum.sort(@public_types)
    assert digest(normalized_types) == @types_digest
  end

  test "the extracted facade preserves docs and semantic default signatures" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Commercial)

    function_docs =
      Enum.flat_map(entries, fn
        {{:function, name, arity}, _, signatures, doc, metadata} ->
          [{name, arity, signatures, doc, Map.get(metadata, :defaults, 0)}]

        _other ->
          []
      end)

    status_counts =
      Enum.frequencies_by(function_docs, fn {_name, _arity, _signatures, doc, _defaults} ->
        case doc do
          :hidden -> :hidden
          :none -> :none
          %{} -> :documented
        end
      end)

    represented_arities =
      function_docs
      |> Enum.flat_map(fn {name, arity, _signatures, _doc, defaults} ->
        Enum.map((arity - defaults)..arity, &{name, &1})
      end)
      |> MapSet.new()

    assert length(function_docs) == 42
    assert status_counts == %{documented: 15, hidden: 1, none: 26}
    assert represented_arities == MapSet.new(@public_contract)
    assert digest(Enum.sort(function_docs)) == @docs_digest
  end

  test "the extracted facade preserves every public spec" do
    assert {:ok, specs} = Code.Typespec.fetch_specs(Commercial)

    normalized_specs =
      specs
      |> Enum.flat_map(fn {{name, arity}, definitions} ->
        Enum.map(definitions, fn definition ->
          quoted = Code.Typespec.spec_to_quoted(name, definition)
          {name, arity, Macro.to_string(quoted)}
        end)
      end)
      |> Enum.sort()

    assert length(normalized_specs) == 16
    assert digest(normalized_specs) == @specs_digest
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
