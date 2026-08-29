defmodule Storyarn.Architecture.PlatformFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform

  @public_contract [
    acquire_project_snapshot_export_lease: 1,
    active_project_snapshot_reservations: 1,
    analytics_frontend_config: 1,
    can_accept_member?: 2,
    can_create_project?: 1,
    can_create_project_template?: 1,
    can_create_project_template_version?: 1,
    can_create_workspace?: 1,
    can_invite_member?: 2,
    can_publish_reserved_project?: 1,
    can_upload_asset?: 2,
    can_upload_asset_for_project?: 2,
    cast_onboarding_tutorial: 1,
    commit_project_snapshot_restore_storage_reservation: 6,
    commit_project_storage_reservation: 5,
    complete_onboarding_tutorial: 2,
    create_subscription: 1,
    deliver_async_result: 3,
    deliver_content_activity: 5,
    deliver_content_activity_by_ids: 5,
    deliver_scoped_async_result: 3,
    entitlement_limit: 2,
    extend_project_storage_reservation: 4,
    known_product_metric_project_subtype?: 2,
    known_product_metric_project_type?: 1,
    list_notifications: 1,
    list_notifications: 2,
    mark_all_notifications_read: 1,
    mark_notification_read: 2,
    mark_project_storage_reservation_started: 4,
    onboarding_pending?: 2,
    onboarding_summary: 1,
    onboarding_tutorials: 0,
    plan_retention_hours: 1,
    plans_for_workspace_ids: 1,
    product_metric_project_options: 0,
    product_metric_project_subtypes: 0,
    product_metric_project_subtypes: 1,
    product_metric_project_types: 0,
    project_limits_usage: 1,
    project_snapshot_slot_usage: 1,
    project_storage_reservation_object_prefixes: 1,
    project_usage: 2,
    publish_notification_delivery: 1,
    purge_released_snapshot_export_leases: 1,
    purge_released_snapshot_export_leases: 2,
    react_to_event: 4,
    recover_expired_snapshot_export_leases: 1,
    recover_expired_snapshot_export_leases: 2,
    release_project_storage_reservation: 4,
    renew_project_storage_reservation: 3,
    restart_all_onboarding_tutorials: 1,
    restart_onboarding_tutorial: 2,
    reserve_project_storage: 1,
    settle_expired_snapshot_export_leases_locked: 2,
    snapshot_build_heartbeat_interval_ms: 0,
    snapshot_build_lease_ttl_seconds: 0,
    snapshot_download_export_lease_ttl_seconds: 0,
    snapshot_download_max_transfer_seconds: 0,
    snapshot_download_signed_url_ttl_seconds: 0,
    snapshot_export_lease_retention_seconds: 0,
    snapshot_storage_commit_context?: 2,
    subscribe_notifications: 1,
    track_analytics: 2,
    track_analytics: 3,
    transact_with_workspace_lock: 2,
    transact_with_workspace_lock: 3,
    unread_notification_count: 1,
    with_storage_accounting_lock: 2,
    with_storage_accounting_lock: 3,
    workspace_lock_held?: 1,
    workspace_storage_usage: 1
  ]

  @public_types ~w(notification_delivery_outcome onboarding_summary storage_reservation_receipt storage_reservation_write_error)a

  # Frozen before reorganizing Platform by internal capability, then advanced
  # deliberately when Onboarding and presentation analytics entered through
  # the root facade. These hashes protect semantic signatures, defaults,
  # documentation, types, and specs.
  @docs_digest "371182afb4331fe1b03e884a5717d91dde2727bdf135108c910053dc20459e78"
  @types_digest "63d4a089dc6045025c94c41431311f664aae25f2f5f659db70929324595fa570"
  @specs_digest "e59c2f315cc55c9bdf186cc966933d0626fade4121a61258687f15c395dd7c41"

  test "the root facade preserves every established function and arity" do
    public_functions =
      :functions
      |> Platform.__info__()
      |> Enum.reject(fn {name, _arity} -> name in [:module_info, :__info__] end)
      |> MapSet.new()

    assert public_functions == MapSet.new(@public_contract)
  end

  test "the root facade is declarative and enters implementation through capability facades" do
    source = File.read!("lib/storyarn/platform.ex")

    refute Regex.match?(~r/^\s*def(?:p|macro|macrop)?\s/m, source)
    assert Regex.scan(~r/^\s*defdelegate\s/m, source) != []
    refute source =~ "Storyarn.Repo"
    refute source =~ "Oban.insert"

    targets =
      ~r/\bto:\s*([A-Z][A-Za-z0-9_.]*)/
      |> Regex.scan(source, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

    assert targets == ~w(Commercial Notifications Onboarding Reactions)
  end

  test "the compiled facade preserves docs and semantic default signatures" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Platform)

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

    assert length(function_docs) == 66
    assert status_counts == %{documented: 38, hidden: 1, none: 27}
    assert represented_arities == MapSet.new(@public_contract)
    assert digest(Enum.sort(function_docs)) == @docs_digest
  end

  test "the compiled facade preserves its stable public types" do
    assert {:ok, types} = Code.Typespec.fetch_types(Platform)

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

  test "the compiled facade preserves every established public spec" do
    assert {:ok, specs} = Code.Typespec.fetch_specs(Platform)

    normalized_specs =
      specs
      |> Enum.flat_map(fn {{name, arity}, definitions} ->
        Enum.map(definitions, fn definition ->
          quoted = Code.Typespec.spec_to_quoted(name, definition)
          {name, arity, Macro.to_string(quoted)}
        end)
      end)
      |> Enum.sort()

    assert length(normalized_specs) == 39
    assert digest(normalized_specs) == @specs_digest
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
