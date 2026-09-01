defmodule Storyarn.Architecture.PersistenceWriteOwnershipTest do
  use ExUnit.Case, async: false

  alias Storyarn.Architecture.DependencyPolicy

  @moduletag timeout: 300_000

  @policy_path "config/architecture_boundaries.exs"
  @transparent_write_delegates @policy_path
                               |> DependencyPolicy.load!()
                               |> Map.fetch!(:shared_persistence_mappings)
                               |> Map.fetch!(:transparent_write_delegates)
  @storyarn_root "lib"
  @sheets_root "lib/storyarn/sheets"
  @reference_tables [:entity_references, :variable_references]
  @owned_inventory_tables [:assets, :localized_texts, :storage_cleanup_requests]
  @aggregate_identity_tables [:project_memberships, :projects, :workspace_memberships, :workspaces]
  @repo_write_functions ~w(
    delete delete! delete_all insert insert! insert_all insert_or_update
    insert_or_update! update update! update_all
  )a
  @multi_write_functions ~w(
    delete delete_all insert insert_all insert_or_update update update_all
  )a
  @repo_raw_sql_functions [:query, :query!, :query_many, :query_many!]
  @direct_persistence_functions @repo_write_functions ++ @repo_raw_sql_functions
  @dynamic_schema_constructor_pattern ~r/\bstruct!?\s*\(/
  @changeset_passthrough_functions ~w(
    add_error assoc_constraint cast cast_embed change check_constraint
    cast_assoc delete_change exclusion_constraint force_change foreign_key_constraint
    no_assoc_constraint optimistic_lock prepare_changes put_assoc put_change
    put_embed unique_constraint unsafe_validate_unique update_change
    validate_acceptance validate_change validate_confirmation validate_exclusion
    validate_format validate_inclusion validate_length validate_number
    validate_required validate_subset
  )a
  @enumerable_callback_functions %{
    each: %{callback: 1, sources: [0]},
    filter: %{callback: 1, sources: [0]},
    flat_map: %{callback: 1, sources: [0]},
    map: %{callback: 1, sources: [0]},
    reject: %{callback: 1, sources: [0]},
    reduce: %{callback: 2, sources: [0, 1]},
    reduce_while: %{callback: 2, sources: [0, 1]}
  }
  @task_callback_functions %{
    async_stream: %{arities: [2, 3], callback: 1, sources: [0]}
  }

  test "Sheets cannot mutate the Flow-owned flow_nodes table" do
    schemas = schema_modules(@sheets_root, "flow_nodes")

    assert schemas != [], "the guard must discover at least one Sheet read model for flow_nodes"

    violations =
      @sheets_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        if String.contains?(source, ["FlowNodeRecord", "flow_nodes"]) do
          table_mutations(source, path, schemas, "flow_nodes")
        else
          []
        end
      end)

    assert violations == [], """
    Sheets may read its consumer-owned FlowNodeRecord projections, but it may not
    mutate flow_nodes. Ordinary cross-context intent must enter the public Flows
    command port; reviewed Project import, restore and reconstitution paths remain
    privileged lifecycle exceptions.

    Violations: #{inspect(violations, pretty: true)}
    """
  end

  test "AST guard detects the removed changeset writer and direct Repo mutations" do
    source = """
    defmodule Example do
      import Ecto.Query

      alias Storyarn.Repo
      alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord

      def update_audio(node_id, audio_asset_id) do
        node = Repo.one(from(node in FlowNodeRecord, where: node.id == ^node_id))

        node
        |> Ecto.Changeset.change(data: %{"audio_asset_id" => audio_asset_id})
        |> Repo.update()
      end

      def create_one(attrs), do: Repo.insert(struct(FlowNodeRecord, attrs))
      def delete_one(%FlowNodeRecord{} = node), do: Repo.delete(node)
      def replace_all(rows), do: Repo.insert_all(FlowNodeRecord, rows)
      def clear_all, do: Repo.delete_all(from(node in FlowNodeRecord))
      def rename_all, do: Repo.update_all("flow_nodes", set: [type: "dialogue"])
    end
    """

    assert source
           |> table_mutations(
             "inline_writer.ex",
             schema_modules(@sheets_root, "flow_nodes"),
             "flow_nodes"
           )
           |> Enum.map(& &1.operation)
           |> Enum.sort() == [:delete, :delete_all, :insert, :insert_all, :update, :update_all]
  end

  test "AST guard detects Ecto.Multi writes, including piped calls and aliased schemas" do
    source = """
    defmodule Example do
      alias Ecto.Multi
      alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord, as: NodeReadModel

      def persist(%NodeReadModel{} = node) do
        changeset = Ecto.Changeset.change(node, data: %{})

        Multi.new()
        |> Multi.insert_all(:new_nodes, NodeReadModel, [])
        |> Multi.update(:node, changeset)
        |> Multi.update_all(:nodes, NodeReadModel, set: [type: "dialogue"])
        |> Multi.delete(:old_node, node)
        |> Multi.delete_all(:remaining_nodes, NodeReadModel)
      end
    end
    """

    assert source
           |> table_mutations(
             "inline_multi.ex",
             schema_modules(@sheets_root, "flow_nodes"),
             "flow_nodes"
           )
           |> Enum.map(& &1.operation)
           |> Enum.sort() == [:delete, :delete_all, :insert_all, :update, :update_all]
  end

  test "AST guard detects injected Repo modules and typed materialization helpers" do
    source = """
    defmodule Example do
      alias Storyarn.Projects.Versioning.MaterializationHelpers
      alias Storyarn.Repo
      alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord

      def run(attrs, entries) do
        {
          insert_direct(Repo, attrs),
          insert_one(Repo, attrs),
          insert_many(Repo, entries)
        }
      end

      def insert_direct(repo, attrs) do
        repo.insert(struct(FlowNodeRecord, attrs))
      end

      def insert_one(repo, attrs) do
        MaterializationHelpers.insert_one_returning_id(repo, FlowNodeRecord, attrs)
      end

      def insert_many(repo, entries) do
        MaterializationHelpers.insert_all(repo, FlowNodeRecord, entries)
      end
    end
    """

    assert source
           |> table_mutations(
             "inline_injected_repo_writer.ex",
             schema_modules(@sheets_root, "flow_nodes"),
             "flow_nodes"
           )
           |> Enum.map(& &1.operation)
           |> Enum.sort() == [:insert, :insert_all, :insert_all]
  end

  test "transparent delegate call sites require attributable Repo and schema arguments" do
    source = """
    defmodule OpaqueMaterializer do
      alias Storyarn.Projects.Versioning.MaterializationHelpers
      alias Storyarn.Repo
      alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord

      def persist(runtime_schema, rows) do
        MaterializationHelpers.insert_all(Repo, runtime_schema, rows)
      end

      def persist_with_untrusted_repo(runtime_repo, rows) do
        MaterializationHelpers.insert_all(runtime_repo, FlowNodeRecord, rows)
      end

      def persist_with_piped_repo(rows) do
        Repo |> MaterializationHelpers.insert_all(FlowNodeRecord, rows)
      end
    end
    """

    calls =
      transparent_delegate_calls_in_source(
        source,
        "lib/storyarn/projects/opaque_materializer.ex"
      )

    assert Enum.map(calls, &{&1.function, &1.operation, &1.repo_attributed?}) == [
             {"def persist/2", :insert_all, true},
             {"def persist_with_untrusted_repo/2", :insert_all, false},
             {"def persist_with_piped_repo/1", :insert_all, true}
           ]

    assert source
           |> table_mutations(
             "lib/storyarn/projects/opaque_materializer.ex",
             schema_modules(@sheets_root, "flow_nodes"),
             "flow_nodes"
           )
           |> Enum.map(&{&1.function, &1.operation}) == [
             {"def persist_with_piped_repo/1", :insert_all}
           ]

    assert_raise ExUnit.AssertionError, ~r/opaque transparent write delegate call/, fn ->
      assert_transparent_delegate_calls_attributed!(calls, [])
    end

    imported_source = """
    defmodule ImportedMaterializer do
      import Storyarn.Projects.Versioning.MaterializationHelpers, only: [insert_all: 3]
    end
    """

    assert [
             %{
               module: "Storyarn.Projects.Versioning.MaterializationHelpers",
               path: "lib/storyarn/projects/imported_materializer.ex"
             }
           ] =
             transparent_delegate_imports_in_source(
               imported_source,
               "lib/storyarn/projects/imported_materializer.ex"
             )

    alternate_dispatch_source = """
    defmodule AlternateDelegateDispatch do
      alias Storyarn.Projects.Versioning.MaterializationHelpers

      def via_apply(repo, schema, rows) do
        apply(MaterializationHelpers, :insert_all, [repo, schema, rows])
      end

      def via_kernel_apply(repo, schema, rows) do
        Kernel.apply(MaterializationHelpers, :insert_one_returning_id, [repo, schema, rows])
      end

      def capture_arity, do: &MaterializationHelpers.insert_all/3
      def capture_arguments, do: &MaterializationHelpers.insert_one_returning_id(&1, &2, &3)
      def function_capture, do: Function.capture(MaterializationHelpers, :insert_all, 3)

      def piped_apply(repo, schema, rows) do
        MaterializationHelpers |> apply(:insert_all, [repo, schema, rows])
      end
    end
    """

    assert alternate_dispatch_source
           |> transparent_delegate_alternate_dispatches_in_source("lib/storyarn/projects/alternate_delegate_dispatch.ex")
           |> Enum.map(&{&1.function, &1.kind}) == [
             {:insert_all, :apply},
             {:insert_one_returning_id, :apply},
             {:insert_all, :capture},
             {:insert_one_returning_id, :capture},
             {:insert_all, :capture},
             {:insert_all, :apply}
           ]
  end

  test "AST guard keeps target taint through changeset validation stages" do
    source = """
    defmodule Example do
      alias Storyarn.Repo
      alias Storyarn.Projects.Assets.Asset

      def persist(%Asset{} = asset, attrs) do
        asset
        |> Ecto.Changeset.change(attrs)
        |> Ecto.Changeset.foreign_key_constraint(:project_id)
        |> Ecto.Changeset.validate_required([:project_id])
        |> Repo.update()
      end
    end
    """

    assert [%{operation: :update}] =
             table_mutations(
               source,
               "inline_validated_changeset_writer.ex",
               schema_modules("lib/storyarn/projects", "assets"),
               "assets"
             )
  end

  test "variable Repo receivers have proven local provenance or a sealed transparent delegate" do
    policy = shared_mapping_policy()

    assert_transparent_write_delegates!(policy)

    unresolved =
      policy.write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(&unresolved_variable_repo_writes(&1, policy.transparent_write_delegates))

    assert unresolved == [], """
    A variable-receiver persistence write has no statically proven Storyarn.Repo
    origin and is not one of the structurally validated transparent delegates.
    Propagate the Repo module through a visible local call, or declare and seal
    the generic delegate so every concrete schema remains attributable at its
    business call site.

    Unresolved writes: #{inspect(unresolved, pretty: true, limit: :infinity)}
    """
  end

  test "alternate and opaque Repo write dispatch is forbidden in application code" do
    source = """
    defmodule UnsafePersistenceDispatch do
      import Storyarn.Repo, only: [delete: 1]

      alias Storyarn.Repo

      def module_capture, do: &Repo.delete/1
      def variable_capture(repo), do: &repo.update/1
      def argument_capture, do: &Repo.insert(&1)
      def function_capture, do: Function.capture(Repo, :delete, 1)
      def applied(repo, record), do: apply(repo, :delete, [record])
      def kernel_applied(repo, record), do: Kernel.apply(repo, :update, [record])
      def piped_apply(record), do: Repo |> apply(:insert, [record])
      def nested_receiver(context, record), do: context.repo.delete(record)
      def fetched_receiver(context, record), do: Map.fetch!(context, :repo).delete(record)
      def runtime_receiver(record), do: runtime_repo().delete(record)
    end
    """

    assert source
           |> unsupported_persistence_dispatches_in_source("inline_unsafe_persistence_dispatch.ex")
           |> Enum.map(&{&1.kind, &1.operation}) == [
             {:repo_import, nil},
             {:capture, :delete},
             {:capture, :update},
             {:capture, :insert},
             {:function_capture, :delete},
             {:apply, :delete},
             {:apply, :update},
             {:apply, :insert},
             {:compound_receiver, :delete},
             {:compound_receiver, :delete},
             {:compound_receiver, :delete}
           ]

    violations =
      @storyarn_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> unsupported_persistence_dispatches_in_source(path)
      end)

    assert violations == [], """
    Persistence writes must remain visible as direct Storyarn.Repo calls or as
    statically proven private Repo parameters. Imports, dynamic dispatch,
    captures and compound Repo receivers hide the physical writer from the
    ownership inventory and are forbidden.

    Violations: #{inspect(violations, pretty: true, limit: :infinity)}
    """
  end

  test "dynamic dispatch on known persistence modules is forbidden" do
    source = """
    defmodule DynamicPersistenceDispatch do
      alias Ecto.Multi
      alias Storyarn.Projects.Versioning.MaterializationHelpers
      alias Storyarn.Repo

      def repo(operation, record), do: apply(Repo, operation, [record])
      def raw_sql(sql), do: apply(Repo, :query!, [sql, []])
      def raw_capture, do: &Repo.query!/2
      def multi(multi, operation, record), do: apply(Multi, operation, [multi, :row, record])

      def delegate(repo, schema, rows, function),
        do: apply(MaterializationHelpers, function, [repo, schema, rows])

      def delegate_capture(function),
        do: Function.capture(MaterializationHelpers, function, 3)
    end
    """

    assert source
           |> unsupported_persistence_dispatches_in_source("inline_dynamic_persistence_dispatch.ex")
           |> Enum.map(&{&1.kind, &1.operation}) == [
             {:apply, :dynamic},
             {:apply, :query!},
             {:capture, :query!},
             {:apply, :dynamic},
             {:apply, :dynamic},
             {:function_capture, :dynamic}
           ]
  end

  test "opaque association persistence constructs are forbidden in application code" do
    source = """
    defmodule OpaqueAssociations do
      import Ecto, only: [build_assoc: 2]
      import Ecto.Changeset, only: [cast_assoc: 2]
      import Enum, only: [each: 2]

      alias Ecto, as: Persistence
      alias Storyarn.Repo

      def build(project), do: Ecto.build_assoc(project, :memberships)
      def build_imported(project), do: build_assoc(project, :memberships)
      def put(changeset, memberships), do: Ecto.Changeset.put_assoc(changeset, :memberships, memberships)
      def cast(changeset), do: cast_assoc(changeset, :memberships)
      def prepare(changeset, callback), do: Ecto.Changeset.prepare_changes(changeset, callback)
      def delete_one(project), do: Repo.delete(project.membership)
      def delete_all(project), do: Enum.each(project.memberships, &Repo.delete/1)

      def delete_all_anonymous(project) do
        Enum.each(project.memberships, fn membership -> Repo.delete(membership) end)
      end

      def delete_aliased(project) do
        membership = project.membership
        Repo.delete(membership)
      end

      def delete_assoc(project), do: Persistence.assoc(project, :memberships) |> Repo.delete_all()
      def delete_pattern(%{memberships: memberships}), do: Repo.delete_all(memberships)
      def delete_map(project), do: Repo.delete(Map.fetch!(project, :membership))
      def delete_get_in(project), do: Repo.delete(get_in(project, [:membership]))
      def delete_imported(project), do: each(project.memberships, &Repo.delete/1)
      def delete_async(project), do: Task.async_stream(project.memberships, &Repo.delete/1)

      def delete_map_every(project) do
        Enum.map_every(project.memberships, 1, fn membership -> Repo.delete(membership) end)
      end

      def delete_supervised(project) do
        Task.Supervisor.async_stream_nolink(
          ExampleSupervisor,
          project.memberships,
          fn membership -> Repo.delete(membership) end
        )
      end

      def delete_nested(project) do
        Enum.each(project.memberships, fn membership ->
          Enum.each([membership], fn row -> Repo.delete(row) end)
        end)
      end

      def delete_tuple(project) do
        {membership, ignored} = {project.membership, :ignored}
        _ignored = ignored
        Repo.delete(membership)
      end
    end
    """

    assert source
           |> opaque_persistence_constructs_in_source("inline_opaque_associations.ex")
           |> Enum.map(&{&1.module, &1.function}) == [
             {"Ecto", :build_assoc},
             {"Ecto", :build_assoc},
             {"Ecto.Changeset", :put_assoc},
             {"Ecto.Changeset", :cast_assoc},
             {"Ecto.Changeset", :prepare_changes}
           ]

    assert [%{module: "Enum"}] =
             opaque_callback_imports_in_source(source, "inline_opaque_associations.ex")

    assert source
           |> opaque_association_write_targets_in_source("inline_opaque_associations.ex")
           |> Enum.map(&{&1.function, &1.operation}) == [
             {"def delete_one/1", :delete},
             {"def delete_all/1", :delete},
             {"def delete_all_anonymous/1", :delete},
             {"def delete_aliased/1", :delete},
             {"def delete_assoc/1", :delete_all},
             {"def delete_pattern/1", :delete_all},
             {"def delete_map/1", :delete},
             {"def delete_get_in/1", :delete},
             {"def delete_imported/1", :delete},
             {"def delete_async/1", :delete},
             {"def delete_map_every/1", :delete},
             {"def delete_supervised/1", :delete},
             {"def delete_nested/1", :delete},
             {"def delete_tuple/1", :delete}
           ]

    violations =
      @storyarn_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> opaque_persistence_constructs_in_source(path)
      end)

    assert violations == [], """
    Association-mutating changeset stages and Ecto.build_assoc hide physical
    table effects from the ownership inventory. Keep association writes
    explicit and independently attributable.

    Violations: #{inspect(violations, pretty: true, limit: :infinity)}
    """

    opaque_write_targets =
      @storyarn_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> opaque_association_write_targets_in_source(path)
      end)

    assert opaque_write_targets == [], """
    A direct field-access association is an opaque persistence target. Load and
    mutate the owned record through an attributable schema/query instead of
    writing a preloaded field implicitly.

    Violations: #{inspect(opaque_write_targets, pretty: true, limit: :infinity)}
    """

    callback_imports =
      @storyarn_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> opaque_callback_imports_in_source(path)
      end)

    assert callback_imports == [], """
    Enum, Stream and Task persistence callbacks must stay qualified so the
    ownership analyzer can identify their collection and callback positions.

    Imports: #{inspect(callback_imports, pretty: true, limit: :infinity)}
    """
  end

  test "generic insert_all targets must be statically closed" do
    opaque_source = """
    defmodule OpaqueBulkWriter do
      alias Storyarn.Repo

      def persist(schema, rows), do: Repo.insert_all(schema, rows)
    end
    """

    opaque_calls = opaque_insert_all_calls_in_source(opaque_source, "inline_opaque_bulk_writer.ex")

    assert_raise ExUnit.AssertionError, ~r/opaque insert_all target/, fn ->
      assert_opaque_insert_all_targets_attributed!(opaque_calls, [])
    end

    attributed_source = """
    defmodule AttributedBulkWriter do
      alias Storyarn.Repo
      alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord

      def persist(rows), do: bulk_insert(FlowNodeRecord, rows)
      defp bulk_insert(schema, rows), do: Repo.insert_all(schema, rows)
    end
    """

    attributed_calls =
      opaque_insert_all_calls_in_source(
        attributed_source,
        "inline_attributed_bulk_writer.ex"
      )

    attributed_writes =
      table_mutations(
        attributed_source,
        "inline_attributed_bulk_writer.ex",
        schema_modules(@sheets_root, "flow_nodes"),
        "flow_nodes"
      )

    assert_opaque_insert_all_targets_attributed!(attributed_calls, attributed_writes)

    mixed_caller_source = """
    defmodule MixedCallerBulkWriter do
      alias Storyarn.Repo
      alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord

      def persist(rows), do: bulk_insert(FlowNodeRecord, rows)
      def persist_runtime(schema, rows), do: bulk_insert(schema, rows)
      defp bulk_insert(schema, rows), do: Repo.insert_all(schema, rows)
    end
    """

    assert [%{function: "defp bulk_insert/2", operation: :insert_all}] =
             opaque_insert_all_calls_in_source(
               mixed_caller_source,
               "inline_mixed_caller_bulk_writer.ex"
             )

    attributed_table_source = """
    defmodule AttributedTableWriter do
      alias Storyarn.Repo

      @target "flow_nodes"

      def persist(rows), do: Repo.insert_all(@target, rows)
    end
    """

    assert attributed_table_source
           |> table_mutations(
             "inline_attributed_table_writer.ex",
             [],
             "flow_nodes"
           )
           |> Enum.map(&{&1.function, &1.operation}) == [
             {"def persist/1", :insert_all}
           ]

    composed_table_source = """
    defmodule ComposedTableWriter do
      alias Storyarn.Repo

      @prefix "flow_"
      @target @prefix <> "nodes"

      def persist(rows), do: Repo.insert_all(@target, rows)
    end
    """

    assert [%{function: "def persist/1", operation: :insert_all}] =
             opaque_insert_all_calls_in_source(
               composed_table_source,
               "inline_composed_table_writer.ex"
             )

    calls =
      shared_mapping_policy().write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> opaque_insert_all_calls_in_source(path)
      end)

    assert calls == [], """
    Production contains an insert_all target whose complete private caller set
    is not statically restricted to literal schemas or table names.

    Opaque calls: #{inspect(calls, pretty: true, limit: :infinity)}
    """
  end

  test "runtime schema constructors cannot hide a persistence target" do
    source = """
    defmodule RuntimeSchemaWriter do
      alias Storyarn.Repo

      def persist(schema, attrs), do: Repo.insert(struct(schema, attrs))
    end
    """

    assert [%{function: "def persist/2", operation: :insert}] =
             opaque_dynamic_schema_writes_in_source(source, "inline_runtime_schema_writer.ex")

    hidden_source = """
    defmodule HiddenRuntimeSchemaWriter do
      alias Storyarn.Repo

      def persist(schema, attrs), do: Repo.insert(build(schema, attrs))
      defp build(schema, attrs) do
        record = struct(schema, attrs)
        record
      end
    end
    """

    assert [%{function: "def persist/2", operation: :insert}] =
             opaque_dynamic_schema_writes_in_source(hidden_source, "inline_hidden_runtime_schema_writer.ex")

    violations =
      @storyarn_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> opaque_dynamic_schema_writes_in_source(path)
      end)

    assert violations == [], """
    Runtime schema construction hides the physical table from the ownership
    inventory. Keep the schema literal at the write site or propagate it only
    through a private helper whose complete caller set is statically closed.

    Violations: #{inspect(violations, pretty: true, limit: :infinity)}
    """
  end

  test "Repo provenance does not trust a fallback that may return an arbitrary module" do
    source = """
    defmodule UnsafeRepoFallback do
      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo

      def insert(untrusted_repo, attrs) do
        repo = untrusted_repo || Repo
        repo.insert(struct(Asset, attrs))
      end

      def insert_before_rebind(repo, attrs) do
        repo.insert(struct(Asset, attrs))
        repo = Repo
        repo
      end
    end
    """

    assert source
           |> unresolved_variable_repo_writes_in_source(
             "inline_unsafe_repo_fallback.ex",
             []
           )
           |> Enum.map(&{&1.function, &1.operation, &1.receiver}) == [
             {"def insert/2", :insert, :repo},
             {"def insert_before_rebind/2", :insert, :repo}
           ]
  end

  test "Repo provenance requires every call site and rejects rebinding and opaque pipes" do
    source = """
    defmodule UnsafeRepoPropagation do
      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo

      def safe_entry(attrs), do: persist_from_mixed_callers(Repo, attrs)
      def unsafe_entry(runtime_repo, attrs), do: persist_from_mixed_callers(runtime_repo, attrs)

      def public_writer(repo, attrs) do
        repo.insert(struct(Asset, attrs))
      end

      def call_public_writer(attrs), do: public_writer(Repo, attrs)

      def captured_writer(attrs) do
        persist_from_capture(Repo, attrs)
        Enum.reduce(runtime_repos(), attrs, &persist_from_capture/2)
      end

      defp persist_from_mixed_callers(repo, attrs) do
        repo.insert(struct(Asset, attrs))
      end

      def rebind_entry(attrs), do: persist_after_rebind(Repo, attrs)

      defp persist_after_rebind(repo, attrs) do
        repo = runtime_repo()
        repo.insert(struct(Asset, attrs))
      end

      defp persist_from_capture(repo, attrs) do
        repo.insert(struct(Asset, attrs))
      end

      def piped_entry(runtime_repo, attrs) do
        struct(Asset, attrs) |> runtime_repo.insert()
      end

      defp runtime_repo, do: Repo
    end
    """

    assert source
           |> unresolved_variable_repo_writes_in_source(
             "inline_unsafe_repo_propagation.ex",
             []
           )
           |> Enum.map(&{&1.function, &1.operation, &1.receiver}) == [
             {"def public_writer/2", :insert, :repo},
             {"defp persist_from_mixed_callers/2", :insert, :repo},
             {"defp persist_after_rebind/2", :insert, :repo},
             {"defp persist_from_capture/2", :insert, :repo},
             {"def piped_entry/2", :insert, :runtime_repo}
           ]
  end

  test "Repo provenance never trusts a non-canonical module aliased as Repo" do
    source = """
    defmodule UnsafeRepoAlias do
      alias Some.OtherRepo, as: Repo
      alias Storyarn.Projects.Assets.Asset

      def run(attrs), do: persist(Repo, attrs)
      defp persist(repo, attrs), do: repo.insert(struct(Asset, attrs))
    end
    """

    assert source
           |> unresolved_variable_repo_writes_in_source("inline_unsafe_repo_alias.ex", [])
           |> Enum.map(&{&1.function, &1.operation, &1.receiver}) == [
             {"defp persist/2", :insert, :repo}
           ]
  end

  test "Repo provenance resolves canonical alias chains and rejects ambiguous aliases" do
    canonical_source = """
    defmodule CanonicalRepoAliasChain do
      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo, as: Persistence
      alias Persistence, as: Database

      def run(attrs), do: persist(Database, attrs)
      defp persist(repo, attrs), do: repo.insert(struct(Asset, attrs))
    end
    """

    assert unresolved_variable_repo_writes_in_source(
             canonical_source,
             "inline_canonical_repo_alias_chain.ex",
             []
           ) == []

    ambiguous_source = """
    defmodule AmbiguousRepoAlias do
      alias Some.OtherRepo, as: Persistence
      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo, as: Persistence

      def run(attrs), do: persist(Persistence, attrs)
      defp persist(repo, attrs), do: repo.insert(struct(Asset, attrs))
    end
    """

    assert ambiguous_source
           |> unresolved_variable_repo_writes_in_source("inline_ambiguous_repo_alias.ex", [])
           |> Enum.map(&{&1.function, &1.operation, &1.receiver}) == [
             {"defp persist/2", :insert, :repo}
           ]

    ambiguous_direct_source = """
    defmodule AmbiguousDirectRepoAlias do
      alias Some.OtherRepo, as: Database
      alias Storyarn.Repo, as: Database

      def remove(record), do: Database.delete(record)
      def capture, do: &Database.delete/1
      def raw(sql), do: Database.query!(sql, [])
      def opaque_raw(context, sql), do: context.repo.query!(sql, [])
    end
    """

    assert ambiguous_direct_source
           |> unsupported_persistence_dispatches_in_source("inline_ambiguous_direct_repo_alias.ex")
           |> Enum.map(&{&1.kind, &1.operation}) == [
             {:ambiguous_persistence_alias, :delete},
             {:capture, :delete},
             {:ambiguous_persistence_alias, :query!},
             {:compound_receiver, :query!}
           ]
  end

  test "AST guard follows typed records and changesets through local helper boundaries" do
    source = """
    defmodule Example do
      alias Storyarn.Repo
      alias Storyarn.Projects.Assets.Asset

      def persist(attrs) do
        asset = %Asset{}
        changeset = Ecto.Changeset.change(asset, attrs)
        forward(changeset)
      end

      defp forward(changeset), do: insert_asset(changeset)
      defp insert_asset(changeset), do: Repo.insert(changeset)

      def update_asset(%Asset{} = asset) do
        asset
        |> Ecto.Changeset.change(filename: "renamed")
        |> persist_update()
      end

      defp persist_update(changeset), do: changeset |> Repo.update()
    end
    """

    assert source
           |> table_mutations("inline_helpers.ex", ["Storyarn.Projects.Assets.Asset"], "assets")
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"defp insert_asset/1", :insert},
             {"defp persist_update/1", :update}
           ]
  end

  test "AST guard keeps target taint in compound schema patterns" do
    source = """
    defmodule Example do
      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo
      alias Storyarn.Workspaces.WorkspaceMembership

      def remove({%Asset{} = asset, %WorkspaceMembership{} = _membership} = pair) do
        _pair = pair
        Repo.delete(asset)
      end
    end
    """

    assert source
           |> table_mutations("inline_compound_pattern.ex", ["Storyarn.Projects.Assets.Asset"], "assets")
           |> Enum.map(&{&1.function, &1.operation}) == [{"def remove/1", :delete}]
  end

  test "AST guard requires a declared schema target and ignores unrelated Repo writes" do
    source = """
    defmodule Example do
      alias Storyarn.Projects.ProjectMembership
      alias Storyarn.Repo
      alias Storyarn.Workspaces.WorkspaceMembership

      def create(%{membership_schema: ProjectMembership}) do
        %ProjectMembership{}
        |> Ecto.Changeset.change(%{})
        |> Repo.insert()
      end

      def update(%ProjectMembership{} = membership) do
        membership
        |> Ecto.Changeset.change(%{})
        |> Repo.update()
      end

      def unrelated(%WorkspaceMembership{} = membership) do
        membership
        |> Ecto.Changeset.change(%{})
        |> Repo.update()
      end
    end
    """

    assert source
           |> table_mutations(
             "inline_target_bound_writer.ex",
             ["Storyarn.Projects.ProjectMembership"],
             "project_memberships"
           )
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [{"def create/1", :insert}, {"def update/1", :update}]
  end

  test "AST guard follows the record selected from joined queries" do
    source = """
    defmodule Example do
      import Ecto.Query

      alias Storyarn.Projects.References.Persistence.BlockRecord
      alias Storyarn.Projects.References.Persistence.TableRowRecord
      alias Storyarn.Repo

      def update_primary do
        row =
          Repo.one!(
            from(row in TableRowRecord,
              join: block in BlockRecord,
              on: block.id == row.block_id
            )
          )

        row |> Ecto.Changeset.change(cells: %{}) |> Repo.update()
      end

      def update_joined do
        block =
          Repo.one!(
            from(row in TableRowRecord,
              join: block in BlockRecord,
              on: block.id == row.block_id,
              select: block
            )
          )

        block |> Ecto.Changeset.change(data: %{}) |> Repo.update()
      end

      def update_joined_from_prebuilt_query do
        query =
          from(row in TableRowRecord,
            join: block in BlockRecord,
            on: block.id == row.block_id
          )

        block = query |> select([_row, block], block) |> Repo.one!()
        block |> Ecto.Changeset.change(data: %{}) |> Repo.update()
      end

      def update_named_joined_from_prebuilt_query do
        query =
          from(row in TableRowRecord,
            join: block in BlockRecord,
            as: :block,
            on: block.id == row.block_id
          )

        block = query |> select([block: block], block) |> Repo.one!()
        block |> Ecto.Changeset.change(data: %{}) |> Repo.update()
      end

      def update_selected_map do
        row = Repo.one!(from(row in TableRowRecord, select: %{row | cells: %{}}))
        row |> Ecto.Changeset.change(cells: %{}) |> Repo.update()
      end

      def update_selected_struct do
        row = Repo.one!(from(row in TableRowRecord, select: struct(row, [:id, :cells])))
        row |> Ecto.Changeset.change(cells: %{}) |> Repo.update()
      end

      def update_joined_association do
        block =
          Repo.one!(
            from(row in TableRowRecord,
              join: block in assoc(row, :block),
              select: block
            )
          )

        block |> Ecto.Changeset.change(data: %{}) |> Repo.update()
      end
    end
    """

    assert source
           |> table_mutations(
             "inline_joined_query.ex",
             ["Storyarn.Projects.References.Persistence.BlockRecord"],
             "blocks"
           )
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"def update_joined/0", :update},
             {"def update_joined_association/0", :update},
             {"def update_joined_from_prebuilt_query/0", :update},
             {"def update_named_joined_from_prebuilt_query/0", :update}
           ]

    assert source
           |> table_mutations(
             "inline_joined_query.ex",
             ["Storyarn.Projects.References.Persistence.TableRowRecord"],
             "table_rows"
           )
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"def update_joined_from_prebuilt_query/0", :update},
             {"def update_named_joined_from_prebuilt_query/0", :update},
             {"def update_primary/0", :update},
             {"def update_selected_map/0", :update},
             {"def update_selected_struct/0", :update}
           ]
  end

  test "AST guard discovers association-selected writers without a target marker" do
    source = """
    defmodule Example do
      import Ecto.Query

      alias Storyarn.Projects.References.Persistence.TableRowRecord
      alias Storyarn.Repo

      def update_joined_association do
        block =
          Repo.one!(
            from(row in TableRowRecord,
              join: block in assoc(row, :block),
              select: block
            )
          )

        block |> Ecto.Changeset.change(data: %{}) |> Repo.update()
      end
    end
    """

    markers = [
      "blocks",
      "Storyarn.Projects.References.Persistence.BlockRecord",
      "BlockRecord"
    ]

    refute String.contains?(source, markers)
    assert shared_source_candidate?(source, markers)

    assert source
           |> table_mutations(
             "inline_assoc_query.ex",
             ["Storyarn.Projects.References.Persistence.BlockRecord"],
             "blocks"
           )
           |> Enum.map(&{&1.function, &1.operation}) == [
             {"def update_joined_association/0", :update}
           ]
  end

  test "AST guard propagates target values into case branch patterns" do
    source = """
    defmodule Example do
      alias Storyarn.Projects.Persistence.BlockRecord
      alias Storyarn.Repo

      def delete_block(id) do
        case Repo.get(BlockRecord, id) do
          nil -> :ok
          block -> Repo.delete(block)
        end
      end
    end
    """

    assert source
           |> table_mutations(
             "inline_case_binding.ex",
             ["Storyarn.Projects.Persistence.BlockRecord"],
             "blocks"
           )
           |> Enum.map(&{&1.function, &1.operation}) == [{"def delete_block/1", :delete}]
  end

  test "AST guard follows target collections through pipelines and callbacks" do
    source = """
    defmodule Example do
      import Ecto.Query

      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo

      def purge(project_id) do
        Asset
        |> where([asset], asset.project_id == ^project_id)
        |> Repo.all()
        |> delete_rows()
      end

      defp delete_rows(rows) do
        Enum.reduce_while(rows, :ok, fn row, _result ->
          case Repo.delete(row) do
            {:ok, _row} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end

      def delete_direct(%Asset{} = asset), do: Enum.each([asset], &Repo.delete/1)
    end
    """

    assert source
           |> table_mutations("inline_callback.ex", ["Storyarn.Projects.Assets.Asset"], "assets")
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [{"def delete_direct/1", :delete}, {"defp delete_rows/1", :delete}]
  end

  test "AST guard propagates target callback captures without leaking variable names between functions" do
    source = """
    defmodule Example do
      alias Storyarn.Projects.Assets.StorageCleanupRequest
      alias Storyarn.Repo

      def retry_all do
        requests = Repo.all(StorageCleanupRequest)
        Enum.each(requests, &consume(&1))
      end

      defp consume(request), do: request |> Repo.delete()

      defp unrelated(request) do
        Repo.delete(request)
      end
    end
    """

    assert source
           |> table_mutations(
             "inline_capture.ex",
             ["Storyarn.Projects.Assets.StorageCleanupRequest"],
             "storage_cleanup_requests"
           )
           |> Enum.map(&{&1.function, &1.operation}) == [{"defp consume/1", :delete}]
  end

  test "AST guard resolves module-attribute SQL writes and writable CTEs" do
    source = ~S'''
    defmodule Example do
      alias Storyarn.Repo

      @upsert_sql """
      INSERT INTO localized_texts (id, source_text)
      VALUES ($1, $2)
      ON CONFLICT (id) DO UPDATE SET source_text = EXCLUDED.source_text
      """

      def upsert(values), do: Repo.query!(@upsert_sql, values)

      def purge(ids) do
        Repo.query!("WITH doomed AS (SELECT unnest($1::bigint[]) AS id) DELETE FROM localized_texts USING doomed", [ids])
      end

      def purge_piped(ids) do
        "DELETE FROM localized_texts WHERE id = ANY($1)"
        |> Repo.query!([ids])
      end

      def read, do: Repo.query!("SELECT * FROM localized_texts")
    end
    '''

    assert source
           |> table_mutations("inline_sql.ex", [], "localized_texts")
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"def purge/1", :delete},
             {"def purge_piped/1", :delete},
             {"def upsert/1", :insert}
           ]
  end

  test "AST guard resolves Ecto.Adapters.SQL writes through aliases, imports and pipes" do
    source = ~S'''
    defmodule Example do
      alias Ecto.Adapters.SQL
      alias Ecto.Adapters.SQL, as: DatabaseSQL
      alias Storyarn.Repo

      import Ecto.Adapters.SQL, only: [query!: 3]

      def direct, do: Ecto.Adapters.SQL.query!(Repo, "UPDATE flow_nodes SET type = 'hub'", [])
      def aliased, do: SQL.query(Repo, "DELETE FROM flow_nodes", [])
      def imported, do: query!(Repo, "INSERT INTO flow_nodes (id) VALUES (1)", [])

      def piped do
        Repo
        |> DatabaseSQL.query_many!("DELETE FROM flow_nodes", [])
      end

      def read, do: SQL.query!(Repo, "SELECT * FROM flow_nodes", [])
    end
    '''

    assert source
           |> table_mutations("inline_ecto_sql.ex", [], "flow_nodes")
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"def aliased/0", :delete},
             {"def direct/0", :update},
             {"def imported/0", :insert},
             {"def piped/0", :delete}
           ]
  end

  test "AST guard resolves colliding SQL imports by function and arity" do
    source = ~S'''
    defmodule Example do
      alias Storyarn.Repo

      import Storyarn.Repo, only: [query!: 2]
      import Ecto.Adapters.SQL, only: [query!: 3]

      def via_repo, do: query!("UPDATE flow_nodes SET type = 'dialogue'", [])
      def via_ecto_sql, do: query!(Repo, "DELETE FROM flow_nodes", [])
    end
    '''

    assert source
           |> table_mutations("inline_colliding_sql_imports.ex", [], "flow_nodes")
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"def via_ecto_sql/0", :delete},
             {"def via_repo/0", :update}
           ]
  end

  test "AST guard gives an explicit Ecto.Adapters.SQL alias precedence over its local name" do
    source = ~S'''
    defmodule Example do
      alias Storyarn.Repo, as: StoryRepo
      alias Ecto.Adapters.SQL, as: Repo

      def mutate, do: Repo.query!(StoryRepo, "UPDATE flow_nodes SET type = 'dialogue'", [])
    end
    '''

    assert source
           |> table_mutations("inline_colliding_sql_alias.ex", [], "flow_nodes")
           |> Enum.map(&{&1.function, &1.operation}) == [{"def mutate/0", :update}]
  end

  test "AST guard does not attribute local functions to macro-only SQL imports" do
    source = ~S'''
    defmodule Example do
      import Ecto.Adapters.SQL, only: :macros

      def query!(_repo, _sql, _params), do: :local
      def local_call, do: query!(:repo, "UPDATE flow_nodes SET type = 'dialogue'", [])
    end
    '''

    assert table_mutations(source, "inline_macro_only_sql_import.ex", [], "flow_nodes") == []
  end

  test "AST guard respects a later SQL reimport that excludes the function" do
    source = ~S'''
    defmodule Example do
      import Ecto.Adapters.SQL, only: [query!: 3]
      import Ecto.Adapters.SQL, except: [query!: 3]

      def query!(_repo, _sql, _params), do: :local
      def local_call, do: query!(:repo, "UPDATE flow_nodes SET type = 'dialogue'", [])
    end
    '''

    assert table_mutations(source, "inline_reimported_sql.ex", [], "flow_nodes") == []
  end

  test "AST guard fails closed when raw SQL cannot be resolved" do
    source = """
    defmodule Example do
      alias Storyarn.Repo

      def mutate(sql), do: Repo.query!(sql, [])
    end
    """

    assert_raise ArgumentError, ~r/cannot resolve raw SQL.*inline_dynamic_sql\.ex.*def mutate\/1/s, fn ->
      table_mutations(source, "inline_dynamic_sql.ex", [], "localized_texts")
    end
  end

  test "unresolved raw SQL cannot hide a statically identifiable Repo write" do
    source = """
    defmodule Example do
      alias Storyarn.Repo
      alias Storyarn.Sheets.Block

      def mutate(sql, attrs) do
        Repo.query!(sql, [])
        Repo.insert(struct(Block, attrs))
      end
    end
    """

    {writes, unresolved} =
      table_mutation_analysis(
        source,
        "inline_dynamic_and_static_sql.ex",
        ["Storyarn.Sheets.Block"],
        "blocks"
      )

    assert Enum.map(writes, &{&1.function, &1.operation}) == [{"def mutate/2", :insert}]
    assert Enum.map(unresolved, & &1.function) == ["def mutate/2"]

    assert_raise ArgumentError, ~r/cannot resolve raw SQL.*inline_dynamic_and_static_sql\.ex/s, fn ->
      table_mutations(
        source,
        "inline_dynamic_and_static_sql.ex",
        ["Storyarn.Sheets.Block"],
        "blocks"
      )
    end
  end

  test "AST guard fails closed for unresolved Ecto.Adapters.SQL" do
    source = """
    defmodule Example do
      alias Ecto.Adapters.SQL
      alias Storyarn.Repo

      def mutate(sql), do: SQL.query!(Repo, sql, [])
    end
    """

    assert_raise ArgumentError, ~r/cannot resolve raw SQL.*inline_dynamic_ecto_sql\.ex.*def mutate\/1/s, fn ->
      table_mutations(source, "inline_dynamic_ecto_sql.ex", [], "localized_texts")
    end
  end

  test "dynamic query receivers expose DML and fail closed for unresolved SQL" do
    source = """
    defmodule DynamicRawSql do
      @read_statement "SELECT id FROM localized_texts"

      def read(repo), do: repo.query(@read_statement, [])
      def locked_read(repo), do: repo.query("SELECT id FROM localized_texts FOR UPDATE", [])

      def delete(repo) do
        repo.query!("DELETE FROM localized_texts WHERE id = 1", [])
      end

      def opaque(repo, sql), do: repo.query(sql, [])
    end
    """

    {writes, unresolved} =
      table_mutation_analysis(
        source,
        "inline_dynamic_raw_sql.ex",
        schema_modules("lib/storyarn/localization", "localized_texts"),
        "localized_texts"
      )

    assert Enum.map(writes, &{&1.function, &1.operation}) == [
             {"def delete/1", :delete}
           ]

    assert Enum.map(unresolved, & &1.function) == ["def opaque/2"]

    assert source
           |> unresolved_variable_repo_writes_in_source(
             "inline_dynamic_raw_sql.ex",
             []
           )
           |> Enum.map(&{&1.function, &1.operation, &1.receiver}) == [
             {"def delete/1", :delete, :repo},
             {"def opaque/2", :unresolved_raw_sql, :repo}
           ]
  end

  test "raw SQL bindings fail closed after any reassignment" do
    source = """
    defmodule ReboundRawSql do
      def known_then_opaque(repo, runtime_sql) do
        sql = "SELECT 1"
        sql = runtime_sql
        repo.query!(sql, [])
      end

      def dml_then_read(repo) do
        sql = "DELETE FROM localized_texts"
        repo.query!(sql, [])
        sql = "SELECT 1"
        sql
      end

      def opaque_then_read(repo, runtime_sql) do
        sql = runtime_sql
        repo.query!(sql, [])
        sql = "SELECT 1"
        sql
      end

      def read_then_dml(repo) do
        sql = "SELECT 1"
        sql = "DELETE FROM localized_texts"
        repo.query!(sql, [])
      end

      def runtime_parameter_then_read(repo, sql) do
        repo.query!(sql, [])
        sql = "SELECT 1"
        sql
      end

      def commented_delete(repo) do
        repo.query!("/* audit marker */ DELETE FROM localized_texts", [])
      end
    end
    """

    assert source
           |> unresolved_variable_repo_writes_in_source("inline_rebound_raw_sql.ex", [])
           |> Enum.map(&{&1.function, &1.operation, &1.receiver}) == [
             {"def known_then_opaque/2", :unresolved_raw_sql, :repo},
             {"def dml_then_read/1", :unresolved_raw_sql, :repo},
             {"def opaque_then_read/2", :unresolved_raw_sql, :repo},
             {"def read_then_dml/1", :unresolved_raw_sql, :repo},
             {"def runtime_parameter_then_read/2", :unresolved_raw_sql, :repo},
             {"def commented_delete/1", :delete, :repo}
           ]
  end

  test "every opaque raw SQL call matches the exact reviewed inventory" do
    actual =
      @storyarn_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> unresolved_raw_sql_calls_in_source(path)
      end)
      |> Enum.map(&Map.take(&1, [:function, :path]))
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.path, &1.function})

    expected =
      shared_mapping_policy().reviewed_dynamic_writers
      |> Enum.map(&Map.take(&1, [:function, :path]))
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.path, &1.function})

    assert actual == expected, """
    Dynamic Repo or Ecto.Adapters.SQL statements are fail-closed even when the
    source file does not mention a known table. Every exception must match the
    exact reviewed path/function inventory and its separately pinned digest.

    Actual: #{inspect(actual, pretty: true, limit: :infinity)}
    Expected: #{inspect(expected, pretty: true, limit: :infinity)}
    """
  end

  test "AST guard detects statically dispatched apply writes" do
    source = """
    defmodule Example do
      import Storyarn.Repo, only: [insert: 1]

      alias Storyarn.Projects.Assets.Asset
      alias Storyarn.Repo

      def remove(%Asset{} = asset), do: apply(Repo, :delete, [asset])
      def insert_piped(%Asset{} = asset), do: asset |> insert()
      def insert_with_piped_apply(%Asset{} = asset), do: Repo |> apply(:insert, [asset])
    end
    """

    assert source
           |> table_mutations("inline_apply.ex", ["Storyarn.Projects.Assets.Asset"], "assets")
           |> Enum.map(&{&1.function, &1.operation})
           |> Enum.sort() == [
             {"def insert_piped/1", :insert},
             {"def insert_with_piped_apply/1", :insert},
             {"def remove/1", :delete}
           ]
  end

  test "AST guard permits Flow reads and writes to Sheet-owned projection records" do
    source = """
    defmodule Example do
      import Ecto.Query

      alias Ecto.Multi
      alias Storyarn.Repo
      alias Storyarn.Sheets.References.Projections.FlowNodeRecord
      alias Storyarn.Sheets.References.Projections.VariableReferenceRecord

      def rebuild do
        nodes = Repo.all(from(node in FlowNodeRecord, where: is_nil(node.deleted_at)))
        entries = Enum.map(nodes, &%{flow_node_id: &1.id})

        Repo.insert_all(VariableReferenceRecord, entries, on_conflict: :nothing)
      end

      def queue_reference(multi, reference) do
        changeset = Ecto.Changeset.change(reference, kind: "read")
        Multi.update(multi, :reference, changeset)
      end
    end
    """

    assert table_mutations(
             source,
             "inline_reader.ex",
             schema_modules(@sheets_root, "flow_nodes"),
             "flow_nodes"
           ) == []
  end

  test "reference projections declare source owners and exact writer roles" do
    contracts = reference_ownership_policy()

    assert contracts |> Map.keys() |> Enum.sort() == @reference_tables

    assert contracts.entity_references.source_owners == %{
             "block" => :sheets,
             "flow_node" => :flows,
             "scene_pin" => :scenes,
             "scene_zone" => :scenes
           }

    assert contracts.variable_references.source_owners == %{
             "flow_node" => :flows,
             "scene_ambient_flow" => :scenes,
             "scene_pin" => :scenes,
             "scene_zone" => :scenes
           }

    for {name, contract} <- contracts do
      assert contract.table == Atom.to_string(name)
      assert contract.analyzer.scanner == "Storyarn.Architecture.PersistenceWriteOwnershipTest.table_mutations/4"
      assert is_binary(contract.analyzer.detects) and contract.analyzer.detects != ""
      assert is_list(contract.analyzer.limits) and contract.analyzer.limits != []

      for role <- [:ordinary_writers, :privileged_writers] do
        writers = Map.fetch!(contract, role)
        paths = Enum.map(writers, & &1.path)

        assert paths == Enum.sort(paths)
        assert paths == Enum.uniq(paths)

        for writer <- writers do
          assert File.regular?(writer.path), "declared reference writer is missing: #{writer.path}"
          assert is_binary(writer.reason) and writer.reason != ""
          assert writer.source_types == writer.source_types |> Enum.uniq() |> Enum.sort()
          assert writer.functions != []
          assert valid_declared_functions?(writer.functions)

          for source_type <- writer.source_types do
            assert Map.has_key?(contract.source_owners, source_type)

            if role == :ordinary_writers do
              assert Map.fetch!(contract.source_owners, source_type) == writer.context
            end
          end

          if role == :privileged_writers do
            assert is_atom(writer.exception)

            assert Enum.any?(writer.source_types, fn source_type ->
                     Map.fetch!(contract.source_owners, source_type) != writer.context
                   end)
          end
        end
      end

      declared = declared_reference_writes(contract)
      assert declared == Enum.uniq(declared), "reference writer effects must be declared once: #{name}"
    end
  end

  test "entity and variable reference mutations match the reviewed ownership inventory" do
    for {name, contract} <- reference_ownership_policy() do
      schemas = schema_modules(@storyarn_root, contract.table)

      assert schemas != [], "the guard must discover at least one schema for #{contract.table}"

      actual = detected_reference_writes(contract.table, schemas)
      expected = declared_reference_writes(contract)

      for declared <- expected do
        assert declared in actual, "declared #{name} writer has no statically detected table effect: #{inspect(declared)}"
      end

      assert actual == expected, """
      #{contract.table} may only be mutated by its exact source-owner writers
      and reviewed privileged workflows. FlowNodeRepair is intentionally absent:
      it does not directly mutate either reference table.

      Actual: #{inspect(actual, pretty: true)}
      Expected: #{inspect(expected, pretty: true)}

      Analyzer limits: #{inspect(contract.analyzer.limits, pretty: true)}
      """
    end
  end

  test "assets, localized texts and cleanup requests match their complete writer inventories" do
    contracts = owned_inventory_policy()

    assert contracts |> Map.keys() |> Enum.sort() == @owned_inventory_tables

    for {name, contract} <- contracts do
      schemas = schema_modules(@storyarn_root, contract.table)

      assert schemas != [], "the guard must discover at least one schema for #{contract.table}"
      assert is_atom(contract.ownership_model)
      assert contract.analyzer.scanner == "Storyarn.Architecture.PersistenceWriteOwnershipTest.table_mutations/4"

      for role <- [:ordinary_writers, :privileged_writers] do
        writers = Map.fetch!(contract, role)
        paths = Enum.map(writers, & &1.path)

        assert paths == Enum.sort(paths)
        assert paths == Enum.uniq(paths)

        for writer <- writers do
          assert File.regular?(writer.path), "declared #{name} writer is missing: #{writer.path}"
          assert is_atom(writer.context)
          assert is_binary(writer.reason) and writer.reason != ""
          assert valid_declared_functions?(writer.functions)

          if role == :privileged_writers do
            assert is_atom(writer.exception)
          end
        end
      end

      actual = detected_reference_writes(contract.table, schemas)
      expected = declared_reference_writes(contract)

      assert actual == expected, """
      #{contract.table} may only be mutated by its complete reviewed writer
      inventory. Folder membership alone never grants persistence authority.

      Actual: #{inspect(actual, pretty: true)}
      Expected: #{inspect(expected, pretty: true)}

      Analyzer limits: #{inspect(contract.analyzer.limits, pretty: true)}
      """
    end
  end

  test "cleanup request consumers stay append-only and Projects retains lifecycle authority" do
    contract = owned_inventory_policy().storage_cleanup_requests

    assert contract.ownership_model == :append_only_consumer_requests_projects_lifecycle
    assert contract.request_owners == [:flows, :scenes, :sheets]
    assert contract.lifecycle_owner == :projects

    appenders =
      Enum.filter(contract.ordinary_writers, &(&1.write_authority == :append_storage_compensation_request))

    assert Enum.map(appenders, & &1.context) == contract.request_owners

    for writer <- appenders do
      assert writer.functions == [%{identity: "defp persist_cleanup_request/1", operations: [:insert]}]
      assert File.regular?(writer.request_record_path)

      source = File.read!(writer.path)
      record_source = File.read!(writer.request_record_path)

      assert source =~ ".#{writer.request_changeset}("
      assert record_source =~ ~s|put_change(:owner_kind, "storage_compensation")|
    end

    assert Enum.any?(contract.ordinary_writers, fn writer ->
             writer.context == :projects and writer.write_authority == :full_lifecycle
           end)
  end

  test "aggregate identity and membership tables match their complete ENG-108 writer inventories" do
    contracts = aggregate_identity_policy()

    assert contracts |> Map.keys() |> Enum.sort() == @aggregate_identity_tables

    for {name, contract} <- contracts do
      schemas = schema_modules(@storyarn_root, contract.table)

      assert schemas != [], "the guard must discover at least one schema for #{contract.table}"
      assert contract.table == Atom.to_string(name)
      assert is_atom(contract.ownership_model)
      assert contract.ordinary_owner in [:projects, :workspaces]
      assert contract.writers != [], "#{contract.table} must keep a non-empty writer inventory"
      assert contract.analyzer.scanner == "Storyarn.Architecture.PersistenceWriteOwnershipTest.table_mutations/4"

      writer_paths = Enum.map(contract.writers, & &1.path)
      assert writer_paths == Enum.sort(writer_paths)
      assert writer_paths == Enum.uniq(writer_paths)

      for writer <- contract.writers do
        assert writer.context == contract.ordinary_owner
        assert is_atom(writer.authority)
        assert is_binary(writer.reason) and writer.reason != ""
        assert File.regular?(writer.path), "declared #{name} writer is missing: #{writer.path}"
        assert valid_eng108_functions?(writer.functions)

        source = File.read!(writer.path)
        available_functions = source_function_identities(source, writer.path)

        for function <- writer.functions do
          assert function.identity in available_functions,
                 "#{writer.path} no longer defines #{function.identity}"

          actual_operations = source_function_write_operations(source, writer.path, function.identity)

          assert Enum.all?(function.operations, &(&1 in actual_operations)), """
          #{writer.path} #{function.identity} no longer contains its declared persistence operation.

          Actual operations: #{inspect(actual_operations)}
          Declared operations: #{inspect(function.operations)}
          """
        end
      end

      for false_positive <- contract.scanner_false_positives do
        assert File.regular?(false_positive.path)
        assert is_binary(false_positive.reason) and false_positive.reason != ""

        source = File.read!(false_positive.path)
        assert false_positive.function in source_function_identities(source, false_positive.path)

        normalized_source =
          source_for_function_identities(source, false_positive.path, [false_positive.function])

        assert sha256(normalized_source) == false_positive.source_sha256,
               "#{false_positive.path} #{false_positive.function} changed; re-audit the alleged scanner false positive"
      end

      actual = detected_reference_writes(contract.table, schemas)
      expected = declared_eng108_scanner_writes(contract)

      assert actual == expected, """
      #{contract.table} acquired, lost or moved a statically visible writer.
      Review the real table effect and update the complete ENG-108 inventory;
      conservative false positives must stay classified explicitly.

      Actual: #{inspect(actual, pretty: true)}
      Expected: #{inspect(expected, pretty: true)}

      Analyzer limits: #{inspect(contract.analyzer.limits, pretty: true)}
      """
    end
  end

  test "canonical owner-membership invariant implementation files stay explicit and non-empty" do
    contract = ownership_invariant_policy()

    assert is_binary(contract.invariant) and contract.invariant != ""
    assert contract.implementations != [], "the duplicated invariant contract must never become vacuous"

    assert contract.implementations
           |> Enum.flat_map(& &1.aggregates)
           |> Enum.uniq()
           |> Enum.sort() == [:project, :workspace]

    declared_paths = contract.implementations |> Enum.map(& &1.path) |> Enum.sort()
    assert declared_paths == Enum.uniq(declared_paths)

    reviewed_non_implementation_paths =
      contract.discovery.reviewed_non_implementations
      |> Enum.map(fn candidate ->
        assert File.regular?(candidate.path)
        assert is_binary(candidate.reason) and candidate.reason != ""
        candidate.path
      end)
      |> Enum.sort()

    assert reviewed_non_implementation_paths == Enum.uniq(reviewed_non_implementation_paths)
    assert MapSet.disjoint?(MapSet.new(declared_paths), MapSet.new(reviewed_non_implementation_paths))
    assert contract.discovery.limits != []
    assert Enum.all?(contract.discovery.limits, &(is_binary(&1) and &1 != ""))

    for implementation <- contract.implementations do
      assert implementation.aggregates != []
      assert implementation.aggregates == implementation.aggregates |> Enum.uniq() |> Enum.sort()
      assert Enum.all?(implementation.aggregates, &(&1 in [:project, :workspace]))
      assert is_atom(implementation.context)
      assert is_atom(implementation.mode)
      assert File.regular?(implementation.path)
      assert implementation.functions != []
      assert implementation.functions == implementation.functions |> Enum.uniq() |> Enum.sort()

      source = File.read!(implementation.path)
      available_functions = source_function_identities(source, implementation.path)

      assert Enum.all?(implementation.functions, &(&1 in available_functions))

      declared_function_source =
        source_for_function_identities(source, implementation.path, implementation.functions)

      assert Enum.all?(
               contract.discovery.required_literals,
               &String.contains?(declared_function_source, &1)
             )

      assert String.contains?(declared_function_source, contract.discovery.owner_role_patterns)
    end

    actual_paths =
      contract.discovery.root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        source = File.read!(path)

        Enum.all?(contract.discovery.required_literals, &String.contains?(source, &1)) and
          String.contains?(source, contract.discovery.owner_role_patterns)
      end)
      |> Enum.sort()

    assert actual_paths != [], "owner-invariant discovery must never become vacuous"

    expected_discovery_paths = Enum.sort(declared_paths ++ reviewed_non_implementation_paths)

    assert actual_paths == expected_discovery_paths, """
    Every source file conservatively identified as implementing owner_id +
    exactly one matching role=owner membership must be reviewed explicitly.
    Candidates that only delegate the decision must also remain classified.
    Do not centralize this business rule merely to satisfy the ratchet.

    Actual: #{inspect(actual_paths, pretty: true)}
    Declared: #{inspect(expected_discovery_paths, pretty: true)}
    """
  end

  test "every shared Ecto table has one reviewed ownership classification" do
    policy = shared_mapping_policy()

    inventory =
      shared_mapping_inventory(
        policy.mapping_root,
        policy.bounded_contexts,
        policy.passive_mapping_roots
      )

    shared = shared_mappings(inventory)

    assert shared != %{}, "shared-mapping discovery must never become vacuous"
    assert policy.mapping_root == "lib/storyarn"
    assert policy.write_root == "lib"

    outside_mapping_schemas =
      policy.write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.starts_with?(&1, policy.mapping_root <> "/"))
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> schema_declarations(path)
        |> Enum.map(&Map.put(&1, :path, path))
      end)

    assert outside_mapping_schemas == [], """
    Ecto mappings are inventoried only below #{policy.mapping_root}. Web,
    operator tooling and other infrastructure may consume context mappings but
    cannot define an invisible schema of their own.

    Outside mappings: #{inspect(outside_mapping_schemas, pretty: true)}
    """

    assert {:ok, classifications} =
             classify_shared_mappings(shared, policy, full_persistence_policy())

    assert classifications |> Map.keys() |> Enum.sort() == shared |> Map.keys() |> Enum.sort()

    for {table, table_classification} <- classifications do
      assert table_classification.owner_contexts == Enum.sort(table_classification.owner_contexts)

      assert table_classification.write_mode in [
               :dedicated_contract,
               :exact_inventory,
               :no_application_writes,
               :owner_context
             ]

      assert table_classification.owner_contexts != []

      if table_classification.write_mode == :no_application_writes do
        assert Enum.all?(table_classification.mappings, &(&1.classification == :passive))
      end

      assert Enum.all?(table_classification.mappings, fn mapping ->
               mapping.classification in [:owner_exact, :owner_writable, :passive, :privileged]
             end),
             "#{table} contains an unclassified Ecto mapping"
    end
  end

  test "foreign mappings remain passive unless every write is an exact reviewed exception" do
    policy = shared_mapping_policy()
    persistence = full_persistence_policy()

    shared =
      policy.mapping_root
      |> shared_mapping_inventory(policy.bounded_contexts, policy.passive_mapping_roots)
      |> shared_mappings()

    assert {:ok, classifications} =
             classify_shared_mappings(shared, policy, persistence)

    actual_writes = shared_table_writes(shared, policy)
    allowed_writes = allowed_shared_exact_writes(policy)
    dedicated_allowances = dedicated_contract_allowances(persistence)
    false_positives = reviewed_shared_false_positives(policy)

    assert_shared_mapping_policy!(shared, classifications, actual_writes, policy, persistence)
    assert_exact_dedicated_contract_inventory!("project_languages", actual_writes, dedicated_allowances)

    violations =
      classifications
      |> Enum.flat_map(fn {table, classification} ->
        actual_writes
        |> Map.fetch!(table)
        |> Enum.reject(fn write ->
          identity = shared_write_identity(table, write)

          shared_write_allowed?(
            classification,
            write,
            identity,
            allowed_writes,
            dedicated_allowances
          ) or
            MapSet.member?(false_positives, identity)
        end)
      end)
      |> Enum.sort_by(&{&1.table, &1.path, &1.function, &1.operation})

    assert violations == [], """
    A shared-table write escaped both its owner and an exact privileged
    exception. A foreign mapping is passive regardless of whether it is placed
    under projections/, records/ or entities/. Review the real workflow, then
    either route it through the owner or declare its exact path/function/write
    operation in shared_persistence_mappings.privileged_writers.

    Violations: #{inspect(violations, pretty: true, limit: :infinity)}
    """
  end

  test "putting a writable foreign mapping in entities or records cannot grant ownership" do
    base = %{
      "blocks" => [
        shared_mapping(
          "blocks",
          :sheets,
          :entities,
          "Storyarn.Sheets.Editor.Entities.Block",
          "lib/storyarn/sheets/editor/entities/block.ex"
        )
      ]
    }

    foreign_entity =
      shared_mapping(
        "blocks",
        :scenes,
        :entities,
        "Storyarn.Scenes.Editor.Entities.BlockRecord",
        "lib/storyarn/scenes/editor/entities/block_record.ex"
      )

    policy = %{shared_mapping_policy() | owner_context_overrides: %{}}

    assert {:error, [{"blocks", {:ambiguous_owner, [:scenes, :sheets]}}]} =
             classify_shared_mappings(
               Map.update!(base, "blocks", &[foreign_entity | &1]),
               policy,
               %{}
             )

    foreign_record = %{
      foreign_entity
      | role: :records,
        path: "lib/storyarn/scenes/editor/records/block_record.ex"
    }

    assert {:ok, %{"blocks" => classification}} =
             classify_shared_mappings(
               Map.update!(base, "blocks", &[foreign_record | &1]),
               policy,
               %{}
             )

    assert Enum.find(classification.mappings, &(&1.path == foreign_record.path)).classification == :passive

    source = ~S"""
    defmodule ExampleForeignWriter do
      alias Storyarn.Repo
      alias Storyarn.Scenes.Editor.Entities.BlockRecord

      def create(attrs), do: Repo.insert(struct(BlockRecord, attrs))
    end
    """

    assert [%{operation: :insert}] =
             table_mutations(
               source,
               foreign_record.path,
               [foreign_record.module],
               foreign_record.table
             )

    for path <- ["lib/storyarn_web/foreign_writer.ex", "lib/mix/tasks/foreign_writer.ex"] do
      assert [%{operation: :insert}] =
               table_mutations(source, path, [foreign_record.module], foreign_record.table)

      assert shared_context_for_write_path(path, policy.bounded_contexts) in [
               :presentation_adapters,
               :infrastructure
             ]
    end

    assert_raise ExUnit.AssertionError, ~r/outside the declared bounded contexts/, fn ->
      shared_context_for_path(
        "lib/storyarn/unknown_root/entities/block_record.ex",
        policy.bounded_contexts,
        policy.passive_mapping_roots
      )
    end

    passive_mapping =
      shared_mapping(
        "blocks",
        :technical_consumer,
        :entities,
        "Storyarn.Workers.BlockRecord",
        "lib/storyarn/workers/entities/block_record.ex",
        false
      )

    assert {:ok, %{"blocks" => passive_classification}} =
             classify_shared_mappings(
               Map.update!(base, "blocks", &[passive_mapping | &1]),
               policy,
               %{}
             )

    assert Enum.find(
             passive_classification.mappings,
             &(&1.path == passive_mapping.path)
           ).classification == :passive

    dynamic_schema = ~S"""
    defmodule Storyarn.Scenes.DynamicRecord do
      use Ecto.Schema

      @table "blocks"
      schema @table do
      end
    end
    """

    assert_raise ExUnit.AssertionError, ~r/non-literal Ecto schema/, fn ->
      shared_mappings_in_source(
        dynamic_schema,
        "lib/storyarn/scenes/editor/records/dynamic_record.ex",
        policy.bounded_contexts,
        policy.passive_mapping_roots
      )
    end

    assert schema_declarations(dynamic_schema, "lib/storyarn_web/dynamic_record.ex") == [
             %{table: :non_literal}
           ]
  end

  test "dedicated contracts reject undeclared assoc-derived writes" do
    source = """
    defmodule RogueProjectMembershipWriter do
      import Ecto.Query

      alias Storyarn.Projects.Project
      alias Storyarn.Repo

      def delete_membership(project_id) do
        Project
        |> where([project], project.id == ^project_id)
        |> join(:inner, [project], membership in assoc(project, :memberships))
        |> select([_project, membership], membership)
        |> Repo.one!()
        |> Repo.delete()
      end
    end
    """

    assert [%{function: "def delete_membership/1", operation: :delete} = write] =
             table_mutations(
               source,
               "lib/storyarn/projects/rogue_membership_writer.ex",
               schema_modules(@storyarn_root, "project_memberships"),
               "project_memberships"
             )

    rogue_identity =
      shared_write_identity(
        "project_memberships",
        Map.merge(write, %{
          path: "lib/storyarn/projects/rogue_membership_writer.ex",
          context: :projects
        })
      )

    allowances = dedicated_contract_allowances(full_persistence_policy())

    refute dedicated_contract_write_allowed?(rogue_identity, allowances)

    assert dedicated_contract_write_allowed?(
             {
               "project_memberships",
               "lib/storyarn/projects/access/commands/membership_operations.ex",
               "def create_membership/4",
               :insert
             },
             allowances
           )

    project_language_insert = {
      "project_languages",
      "lib/storyarn/localization/languages/commands/add.ex",
      "defp insert_language/2",
      :insert
    }

    assert dedicated_contract_write_allowed?(project_language_insert, allowances)

    refute dedicated_contract_write_allowed?(
             put_elem(project_language_insert, 3, :delete),
             allowances
           )

    refute dedicated_contract_write_allowed?(
             put_elem(project_language_insert, 2, "def run/2"),
             allowances
           )
  end

  defp shared_mapping_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> Map.fetch!(:shared_persistence_mappings)
  end

  defp assert_transparent_write_delegates!(policy) do
    delegates = policy.transparent_write_delegates

    assert delegates != []

    assert delegates ==
             delegates
             |> Enum.uniq_by(&{&1.module, &1.function, &1.arity})
             |> Enum.sort_by(&{&1.module, &1.function, &1.arity})

    privileged_entrypoints =
      @policy_path
      |> DependencyPolicy.load!()
      |> Map.fetch!(:privileged_entrypoints)

    for delegate <- delegates do
      assert File.regular?(delegate.path)
      assert delegate.repo_argument == 0
      assert delegate.schema_argument == 1
      assert delegate.operation in @repo_write_functions
      assert is_binary(delegate.reason) and delegate.reason != ""

      source = File.read!(delegate.path)
      ast = quoted!(source, delegate.path)

      assert source =~ "defmodule #{delegate.module}"

      clauses =
        ast
        |> function_clauses()
        |> matching_clauses(delegate.function, delegate.arity)

      assert clauses != [], "transparent delegate is missing: #{delegate.module}.#{delegate.function}/#{delegate.arity}"

      calls = Enum.flat_map(clauses, &variable_receiver_writes/1)

      assert [call] = calls,
             "transparent delegate must contain exactly one physical Repo write: #{delegate.module}.#{delegate.function}/#{delegate.arity}"

      repo_parameter = clauses |> Enum.find(&(&1.id == call.clause_id)) |> parameter_name!(delegate.repo_argument)
      schema_parameter = clauses |> Enum.find(&(&1.id == call.clause_id)) |> parameter_name!(delegate.schema_argument)

      assert call.receiver == repo_parameter
      assert call.operation == delegate.operation
      assert variable_name(Enum.at(call.arguments, 0)) == schema_parameter

      assert Enum.any?(privileged_entrypoints, fn entry ->
               entry.module == delegate.module and entry.path == delegate.path and
                 Keyword.get(entry.functions, delegate.function) == delegate.arity
             end),
             "transparent delegate must be sealed as a privileged entrypoint: #{delegate.module}.#{delegate.function}/#{delegate.arity}"
    end

    shared =
      policy.mapping_root
      |> shared_mapping_inventory(policy.bounded_contexts, policy.passive_mapping_roots)
      |> shared_mappings()

    calls =
      policy.write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> transparent_delegate_calls_in_source(path)
      end)

    assert calls != [], "transparent write delegate call-site discovery must never become vacuous"

    imported_delegates =
      policy.write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> transparent_delegate_imports_in_source(path)
      end)

    assert imported_delegates == [], """
    Transparent write delegates must be called through their qualified module
    name so the persistence analyzer can seal every call site.

    Imports: #{inspect(imported_delegates, pretty: true, limit: :infinity)}
    """

    alternate_dispatches =
      policy.write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> transparent_delegate_alternate_dispatches_in_source(path)
      end)

    assert alternate_dispatches == [], """
    Transparent write delegates must use direct, qualified calls. Dynamic
    apply/capture dispatch bypasses exact Repo/schema attribution and is not
    permitted.

    Alternate dispatches: #{inspect(alternate_dispatches, pretty: true, limit: :infinity)}
    """

    for delegate <- @transparent_write_delegates do
      identity = {delegate.module, delegate.function, delegate.arity}

      assert Enum.any?(calls, &(&1.delegate == identity)),
             "transparent write delegate has no live call site: #{delegate.module}.#{delegate.function}/#{delegate.arity}"
    end

    attributed_writes =
      calls
      |> Enum.map(& &1.path)
      |> Enum.uniq()
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        Enum.flat_map(shared, fn {table, mappings} ->
          table_mutations(source, path, Enum.map(mappings, & &1.module), table)
        end)
      end)

    assert_transparent_delegate_calls_attributed!(calls, attributed_writes)
  end

  defp transparent_delegate_calls_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    clauses = function_clauses(ast)
    literal_attributes = literal_binary_module_attributes(ast)
    proven_schema_parameters = proven_literal_schema_parameters(clauses, literal_attributes)

    repo_parameters =
      fixed_point(MapSet.new(), fn parameters ->
        propagate_repo_parameters(clauses, aliases, parameters)
      end)

    Enum.flat_map(clauses, fn clause ->
      repo_variables = clause_repo_variables(clause, aliases, repo_parameters)

      {_body, calls} =
        clause.body
        |> normalize_pipeline_calls()
        |> Macro.prewalk([], fn node, calls ->
          {node,
           collect_transparent_delegate_call(
             node,
             calls,
             clause,
             path,
             aliases,
             repo_variables,
             literal_attributes,
             proven_schema_parameters
           )}
        end)

      Enum.reverse(calls)
    end)
  end

  defp collect_transparent_delegate_call(
         {{:., _, [{:__aliases__, _, segments}, function]}, meta, arguments},
         calls,
         clause,
         path,
         aliases,
         repo_variables,
         literal_attributes,
         proven_schema_parameters
       )
       when is_atom(function) and is_list(arguments) do
    case transparent_write_delegate(expanded_modules(segments, aliases), function, length(arguments)) do
      nil ->
        calls

      delegate ->
        [
          %{
            delegate: {delegate.module, delegate.function, delegate.arity},
            function: clause.identity,
            line: Keyword.get(meta, :line, clause.line),
            operation: delegate.operation,
            path: path,
            repo_attributed?:
              repo_ast?(
                Enum.at(arguments, delegate.repo_argument),
                aliases,
                repo_variables
              ),
            schema_attributed?:
              statically_named_schema_target?(
                Enum.at(arguments, delegate.schema_argument),
                literal_attributes,
                clause,
                proven_schema_parameters
              )
          }
          | calls
        ]
    end
  end

  defp collect_transparent_delegate_call(
         _node,
         calls,
         _clause,
         _path,
         _aliases,
         _repo_variables,
         _literal_attributes,
         _proven_schema_parameters
       ), do: calls

  defp transparent_delegate_imports_in_source(source, path) do
    aliases = source |> quoted!(path) |> alias_bindings()

    delegate_modules =
      MapSet.new(@transparent_write_delegates, & &1.module)

    {_ast, imports} =
      source
      |> quoted!(path)
      |> Macro.prewalk([], fn
        {:import, _meta, [{:__aliases__, _, segments} | options]} = node, imports ->
          modules = expanded_modules(segments, aliases)

          imported =
            Enum.find(modules, fn module ->
              module_name(module) in delegate_modules and
                transparent_delegate_functions_imported?(module_name(module), options)
            end)

          if imported do
            {node, [%{module: module_name(imported), path: path} | imports]}
          else
            {node, imports}
          end

        node, imports ->
          {node, imports}
      end)

    imports
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.path, &1.module})
  end

  defp transparent_delegate_alternate_dispatches_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)

    {_ast, dispatches} =
      ast
      |> normalize_pipeline_calls()
      |> Macro.prewalk([], fn node, dispatches ->
        case transparent_delegate_alternate_dispatch(node, aliases) do
          nil -> {node, dispatches}
          dispatch -> {node, [Map.put(dispatch, :path, path) | dispatches]}
        end
      end)

    dispatches
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp transparent_delegate_alternate_dispatch({:apply, meta, [module, function, arguments]}, aliases)
       when is_atom(function) and is_list(arguments) do
    alternate_delegate_dispatch(module, function, length(arguments), :apply, meta, aliases)
  end

  defp transparent_delegate_alternate_dispatch(
         {{:., _, [{:__aliases__, _, kernel_segments}, :apply]}, meta, [module, function, arguments]},
         aliases
       )
       when is_atom(function) and is_list(arguments) do
    if Enum.any?(expanded_modules(kernel_segments, aliases), &(module_name(&1) == "Kernel")) do
      alternate_delegate_dispatch(module, function, length(arguments), :apply, meta, aliases)
    end
  end

  defp transparent_delegate_alternate_dispatch(
         {:&, meta, [{:/, _, [{{:., _, [{:__aliases__, _, segments}, function]}, _, []}, arity]}]},
         aliases
       )
       when is_atom(function) and is_integer(arity) do
    alternate_delegate_dispatch(
      {:__aliases__, [], segments},
      function,
      arity,
      :capture,
      meta,
      aliases
    )
  end

  defp transparent_delegate_alternate_dispatch(
         {:&, meta, [{{:., _, [{:__aliases__, _, segments}, function]}, _, arguments}]},
         aliases
       )
       when is_atom(function) and is_list(arguments) do
    alternate_delegate_dispatch(
      {:__aliases__, [], segments},
      function,
      length(arguments),
      :capture,
      meta,
      aliases
    )
  end

  defp transparent_delegate_alternate_dispatch(
         {{:., _, [{:__aliases__, _, function_segments}, :capture]}, meta,
          [{:__aliases__, _, module_segments}, function, arity]},
         aliases
       )
       when is_atom(function) and is_integer(arity) do
    if Enum.any?(expanded_modules(function_segments, aliases), &(module_name(&1) == "Function")) do
      alternate_delegate_dispatch(
        {:__aliases__, [], module_segments},
        function,
        arity,
        :capture,
        meta,
        aliases
      )
    end
  end

  defp transparent_delegate_alternate_dispatch(_node, _aliases), do: nil

  defp alternate_delegate_dispatch(module_ast, function, arity, kind, meta, aliases) do
    modules =
      case module_ast do
        {:__aliases__, _, segments} -> expanded_modules(segments, aliases)
        _other -> []
      end

    case transparent_write_delegate(modules, function, arity) do
      nil -> nil
      delegate -> %{delegate: delegate.module, function: function, kind: kind, line: Keyword.get(meta, :line, 0)}
    end
  end

  defp opaque_persistence_constructs_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)

    {_ast, constructs} =
      Macro.prewalk(ast, [], fn node, constructs ->
        case opaque_persistence_construct(node, aliases, imports) do
          nil -> {node, constructs}
          construct -> {node, [Map.put(construct, :path, path) | constructs]}
        end
      end)

    constructs
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp opaque_persistence_construct(node, aliases, imports) do
    case remote_call(node, aliases) do
      {:ok, "Ecto", :build_assoc, _arguments} ->
        opaque_construct("Ecto", :build_assoc, node)

      {:ok, "Ecto.Changeset", function, _arguments}
      when function in [:cast_assoc, :prepare_changes, :put_assoc] ->
        opaque_construct("Ecto.Changeset", function, node)

      :not_a_remote_call ->
        opaque_imported_changeset_construct(node, imports)

      _other ->
        nil
    end
  end

  defp opaque_imported_changeset_construct({function, _meta, arguments} = node, _imports)
       when function in [:cast_assoc, :prepare_changes, :put_assoc] and is_list(arguments) do
    opaque_construct("Ecto.Changeset", function, node)
  end

  defp opaque_imported_changeset_construct({:build_assoc, _meta, arguments} = node, _imports) when is_list(arguments) do
    opaque_construct("Ecto", :build_assoc, node)
  end

  defp opaque_imported_changeset_construct(_node, _imports), do: nil

  defp opaque_construct(module, function, node) do
    %{module: module, function: function, line: node_line(node)}
  end

  defp opaque_callback_imports_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)

    callback_modules = MapSet.new(["Enum", "Stream", "Task", "Task.Supervisor"])

    {_ast, imports} =
      Macro.prewalk(ast, [], fn
        {:import, meta, [{:__aliases__, _, segments} | rest]} = node, current ->
          imported = imported_callback_module(segments, rest, aliases, callback_modules)

          if imported do
            violation = %{line: Keyword.get(meta, :line, 0), module: imported, path: path}
            {node, [violation | current]}
          else
            {node, current}
          end

        node, current ->
          {node, current}
      end)

    imports |> Enum.reverse() |> Enum.uniq()
  end

  defp imported_callback_module(segments, _import_rest, aliases, callback_modules) do
    segments
    |> expanded_modules(aliases)
    |> Enum.map(&module_name/1)
    |> Enum.find(&MapSet.member?(callback_modules, &1))
  end

  defp node_line({_form, meta, _arguments}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp node_line(_node), do: 0

  defp unsupported_persistence_dispatches_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)

    {_ast, violations} =
      Macro.prewalk(ast, [], fn node, violations ->
        case unsupported_persistence_dispatch(node, aliases) do
          nil ->
            {node, violations}

          violation ->
            {node, [Map.put(violation, :path, path) | violations]}
        end
      end)

    violations
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp unsupported_persistence_dispatch({:import, meta, [{:__aliases__, _, segments} | _options]}, aliases) do
    if repo_module?(expanded_modules(segments, aliases)),
      do: persistence_dispatch_violation(:repo_import, nil, meta)
  end

  defp unsupported_persistence_dispatch({:&, meta, [{:/, _, [{{:., _, [receiver, operation]}, _, []}, arity]}]}, aliases)
       when is_atom(operation) and is_integer(arity) do
    case unsupported_dispatch_operation(receiver, operation, arity, aliases) do
      nil -> nil
      operation -> persistence_dispatch_violation(:capture, operation, meta)
    end
  end

  defp unsupported_persistence_dispatch({:&, meta, [{{:., _, [receiver, operation]}, _, arguments}]}, aliases)
       when is_atom(operation) and is_list(arguments) do
    case unsupported_dispatch_operation(receiver, operation, length(arguments), aliases) do
      nil -> nil
      operation -> persistence_dispatch_violation(:capture, operation, meta)
    end
  end

  defp unsupported_persistence_dispatch(
         {{:., _, [{:__aliases__, _, function_segments}, :capture]}, meta, [receiver, operation, arity]},
         aliases
       ) do
    if module_named?(expanded_modules(function_segments, aliases), "Function") do
      case unsupported_dispatch_operation(receiver, operation, literal_arity(arity), aliases) do
        nil -> nil
        operation -> persistence_dispatch_violation(:function_capture, operation, meta)
      end
    end
  end

  defp unsupported_persistence_dispatch({:apply, meta, [receiver, operation, arguments]}, aliases)
       when is_list(arguments) do
    case unsupported_dispatch_operation(receiver, operation, length(arguments), aliases) do
      nil -> nil
      operation -> persistence_dispatch_violation(:apply, operation, meta)
    end
  end

  defp unsupported_persistence_dispatch(
         {{:., _, [{:__aliases__, _, kernel_segments}, :apply]}, meta, [receiver, operation, arguments]},
         aliases
       )
       when is_list(arguments) do
    if module_named?(expanded_modules(kernel_segments, aliases), "Kernel") do
      case unsupported_dispatch_operation(receiver, operation, length(arguments), aliases) do
        nil -> nil
        operation -> persistence_dispatch_violation(:apply, operation, meta)
      end
    end
  end

  defp unsupported_persistence_dispatch({:|>, meta, [receiver, {:apply, _, [operation, arguments]}]}, aliases)
       when is_list(arguments) do
    case unsupported_dispatch_operation(receiver, operation, length(arguments), aliases) do
      nil -> nil
      operation -> persistence_dispatch_violation(:apply, operation, meta)
    end
  end

  defp unsupported_persistence_dispatch({{:., _, [receiver, operation]}, meta, arguments}, aliases)
       when operation in @direct_persistence_functions and is_list(arguments) and arguments != [] do
    cond do
      repo_shaped_compound_receiver?(receiver) ->
        persistence_dispatch_violation(:compound_receiver, operation, meta)

      operation = ambiguous_persistence_alias_operation(receiver, operation, length(arguments), aliases) ->
        persistence_dispatch_violation(:ambiguous_persistence_alias, operation, meta)

      noncanonical_repo_alias?(receiver, aliases) ->
        persistence_dispatch_violation(:noncanonical_repo_alias, operation, meta)

      true ->
        nil
    end
  end

  defp unsupported_persistence_dispatch(_node, _aliases), do: nil

  defp unsupported_dispatch_operation(receiver, operation, arity, aliases) do
    modules = dispatch_receiver_modules(receiver, aliases)

    persistence_dispatch_operation(modules, operation, arity) ||
      if(
        dynamic_repo_receiver?(receiver, aliases) and
          operation in (@repo_write_functions ++ @repo_raw_sql_functions),
        do: operation
      )
  end

  defp dispatch_receiver_modules({:__aliases__, _, segments}, aliases), do: expanded_modules(segments, aliases)

  defp dispatch_receiver_modules(_receiver, _aliases), do: []

  defp persistence_dispatch_operation(modules, operation, arity) do
    module_names = MapSet.new(modules, &module_name/1)

    cond do
      MapSet.member?(module_names, "Storyarn.Repo") ->
        known_or_dynamic_operation(operation, @repo_write_functions ++ @repo_raw_sql_functions)

      MapSet.member?(module_names, "Ecto.Multi") ->
        known_or_dynamic_operation(operation, @multi_write_functions)

      MapSet.member?(module_names, "Ecto.Adapters.SQL") ->
        known_or_dynamic_operation(operation, @repo_raw_sql_functions)

      Enum.any?(@transparent_write_delegates, &MapSet.member?(module_names, &1.module)) ->
        transparent_delegate_dispatch_operation(module_names, operation, arity)

      true ->
        nil
    end
  end

  defp known_or_dynamic_operation(operation, known) when is_atom(operation) do
    if operation in known, do: operation
  end

  defp known_or_dynamic_operation(_operation, _known), do: :dynamic

  defp transparent_delegate_dispatch_operation(_modules, operation, _arity) when not is_atom(operation), do: :dynamic

  defp transparent_delegate_dispatch_operation(modules, operation, arity) do
    if Enum.any?(@transparent_write_delegates, fn delegate ->
         MapSet.member?(modules, delegate.module) and
           delegate.function == operation and
           (is_nil(arity) or delegate.arity == arity)
       end),
       do: operation
  end

  defp literal_arity(arity) when is_integer(arity), do: arity
  defp literal_arity(_arity), do: nil

  defp ambiguous_persistence_alias_operation({:__aliases__, _, segments}, operation, arity, aliases) do
    modules = expanded_modules(segments, aliases)

    if modules |> Enum.map(&module_name/1) |> Enum.uniq() |> length() > 1,
      do: persistence_dispatch_operation(modules, operation, arity)
  end

  defp ambiguous_persistence_alias_operation(_receiver, _operation, _arity, _aliases), do: nil

  defp dynamic_repo_receiver?({:__aliases__, _, segments}, aliases) do
    repo_module?(expanded_modules(segments, aliases)) or List.last(segments) == :Repo
  end

  defp dynamic_repo_receiver?({name, _, context}, _aliases) when is_atom(name) and is_atom(context), do: true
  defp dynamic_repo_receiver?(_receiver, _aliases), do: true

  defp repo_shaped_compound_receiver?({{:., _, [_source, :repo]}, _, []}), do: true

  defp repo_shaped_compound_receiver?({name, _, arguments}) when is_atom(name) and is_list(arguments),
    do: name |> Atom.to_string() |> String.ends_with?("repo")

  defp repo_shaped_compound_receiver?({{:., _, [_receiver, function]}, _, [_source, :repo | _arguments]})
       when function in [:fetch, :fetch!, :get], do: true

  defp repo_shaped_compound_receiver?(_receiver), do: false

  defp noncanonical_repo_alias?({:__aliases__, _, segments}, aliases) do
    List.last(segments) == :Repo and not repo_module?(expanded_modules(segments, aliases))
  end

  defp noncanonical_repo_alias?(_receiver, _aliases), do: false

  defp persistence_dispatch_violation(kind, operation, meta) do
    %{kind: kind, line: Keyword.get(meta, :line, 0), operation: operation}
  end

  defp opaque_association_write_targets_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    clauses = function_clauses(ast)

    repo_parameters =
      fixed_point(MapSet.new(), fn parameters ->
        propagate_repo_parameters(clauses, aliases, parameters)
      end)

    Enum.flat_map(clauses, fn clause ->
      repo_variables = clause_repo_variables(clause, aliases, repo_parameters)
      association_variables = opaque_association_variables({clause.head, clause.body})

      context = %{
        aliases: aliases,
        association_variables: association_variables,
        imports: imports,
        repo_variables: repo_variables
      }

      {_body, writes} =
        clause.body
        |> normalize_pipeline_calls()
        |> Macro.prewalk([], fn node, writes ->
          {node, collect_opaque_association_write(node, writes, clause, path, context)}
        end)

      writes |> Enum.reverse() |> Enum.uniq()
    end)
  end

  defp collect_opaque_association_write(node, writes, clause, path, context) do
    case opaque_association_write_target(
           node,
           context.aliases,
           context.imports,
           context.repo_variables,
           context.association_variables
         ) do
      nil ->
        writes

      operation ->
        [
          %{
            function: clause.identity,
            line: node_line(node),
            operation: operation,
            path: path
          }
          | writes
        ]
    end
  end

  defp opaque_association_write_target(node, aliases, imports, repo_variables, association_variables) do
    case persistence_write_call(node, aliases, imports, repo_variables) do
      {:ok, kind, operation, arguments, _meta} ->
        if opaque_association_target?(persistence_target(kind, arguments), association_variables), do: operation

      :not_a_write ->
        opaque_association_callback_write(node, aliases, imports, repo_variables, association_variables)
    end
  end

  defp opaque_association_callback_write(node, aliases, imports, repo_variables, association_variables) do
    known_callback_association_write(
      node,
      aliases,
      imports,
      repo_variables,
      association_variables
    ) ||
      structural_callback_association_write(
        node,
        aliases,
        imports,
        repo_variables,
        association_variables
      )
  end

  defp known_callback_association_write(node, aliases, imports, repo_variables, association_variables) do
    with {:ok, arguments, %{callback: callback_index, sources: source_indexes}} <-
           enumerable_callback(node, aliases, imports),
         true <-
           Enum.any?(source_indexes, fn index ->
             arguments
             |> Enum.at(index)
             |> opaque_association_target?(association_variables)
           end),
         callback when not is_nil(callback) <- Enum.at(arguments, callback_index),
         {:ok, operation, _meta} <-
           captured_persistence_write(callback, aliases, imports, repo_variables) do
      operation
    else
      _other -> nil
    end
  end

  defp structural_callback_association_write(node, aliases, imports, repo_variables, association_variables) do
    with {:ok, module, _function, arguments} <- remote_call(node, aliases),
         true <- module in ["Enum", "Stream", "Task", "Task.Supervisor"],
         {callback, operation} when not is_nil(callback) <-
           persistence_callback_argument(arguments, aliases, imports, repo_variables),
         true <-
           Enum.any?(arguments -- [callback], &opaque_association_target?(&1, association_variables)) do
      operation
    else
      _other -> nil
    end
  end

  defp persistence_callback_argument(arguments, aliases, imports, repo_variables) do
    Enum.find_value(arguments, {nil, nil}, fn argument ->
      case captured_persistence_write(argument, aliases, imports, repo_variables) do
        {:ok, operation, _meta} -> {argument, operation}
        :not_a_persistence_capture -> nil
      end
    end)
  end

  defp variable_field_access?({{:., _, [{name, _, context}, _field]}, _, []}) when is_atom(name) and is_atom(context),
    do: true

  defp variable_field_access?(_target), do: false

  defp opaque_association_target?({name, _, context}, association_variables) when is_atom(name) and is_atom(context),
    do: MapSet.member?(association_variables, name)

  defp opaque_association_target?(target, association_variables) do
    variable_field_access?(target) or
      association_selector?(target) or
      map_extraction?(target, association_variables) or
      nested_opaque_association_target?(target, association_variables)
  end

  defp association_selector?({{:., _, [_receiver, :assoc]}, _, arguments}) when is_list(arguments), do: true

  defp association_selector?({:assoc, _, arguments}) when is_list(arguments), do: true
  defp association_selector?(_target), do: false

  defp map_extraction?({{:., _, [_receiver, function]}, _, [source | _arguments]}, variables)
       when function in [:fetch, :fetch!, :get, :get_lazy] do
    opaque_association_target?(source, variables) or variable_ast?(source)
  end

  defp map_extraction?({:get_in, _, [source | _arguments]}, variables) do
    opaque_association_target?(source, variables) or variable_ast?(source)
  end

  defp map_extraction?({{:., _, [{:__aliases__, _, module_segments}, function]}, _, [source | _arguments]}, variables)
       when function in [:fetch, :fetch!, :get, :get_and_update, :get_in, :pop] do
    module = Enum.map_join(module_segments, ".", &Atom.to_string/1)

    module in ["Access", "Kernel"] and
      (opaque_association_target?(source, variables) or variable_ast?(source))
  end

  defp map_extraction?(_target, _variables), do: false

  defp nested_opaque_association_target?({:{}, _, values}, association_variables),
    do: Enum.any?(values, &opaque_association_target?(&1, association_variables))

  defp nested_opaque_association_target?({:%{}, _, pairs}, association_variables) do
    Enum.any?(pairs, fn
      {_key, value} -> opaque_association_target?(value, association_variables)
      value -> opaque_association_target?(value, association_variables)
    end)
  end

  defp nested_opaque_association_target?({left, right}, association_variables) do
    opaque_association_target?(left, association_variables) or
      opaque_association_target?(right, association_variables)
  end

  defp nested_opaque_association_target?(target, association_variables) when is_list(target),
    do: Enum.any?(target, &opaque_association_target?(&1, association_variables))

  defp nested_opaque_association_target?(_target, _association_variables), do: false

  defp variable_ast?({name, _, context}) when is_atom(name) and is_atom(context), do: true
  defp variable_ast?(_target), do: false

  defp opaque_association_variables({head, body}) do
    initial = opaque_pattern_bound_variables(head)
    fixed_point(initial, &propagate_opaque_association_variables(body, &1))
  end

  defp opaque_pattern_bound_variables(pattern) do
    {_pattern, variables} =
      Macro.prewalk(pattern, MapSet.new(), fn
        {:%, _, [_schema, {:%{}, _, fields}]} = node, current ->
          {node, MapSet.union(current, map_pattern_variables(fields))}

        {:%{}, _, fields} = node, current ->
          {node, MapSet.union(current, map_pattern_variables(fields))}

        node, current ->
          {node, current}
      end)

    variables
  end

  defp map_pattern_variables(fields) do
    fields
    |> Enum.flat_map(fn {_key, value} -> variable_names(value) end)
    |> MapSet.new()
  end

  defp propagate_opaque_association_variables(ast, association_variables) do
    {_ast, next} = Macro.prewalk(ast, association_variables, &collect_opaque_association_variable/2)
    next
  end

  defp collect_opaque_association_variable({operator, _, [left, right]} = node, current) when operator in [:=, :<-] do
    next = MapSet.union(current, opaque_pattern_bound_variables(left))

    if opaque_association_target?(right, next),
      do: {node, MapSet.union(next, variable_names(left))},
      else: {node, next}
  end

  defp collect_opaque_association_variable(node, current), do: {node, current}

  defp opaque_insert_all_calls_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    clauses = function_clauses(ast)
    literal_attributes = literal_binary_module_attributes(ast)
    proven_schema_parameters = proven_literal_schema_parameters(clauses, literal_attributes)

    repo_parameters =
      fixed_point(MapSet.new(), fn parameters ->
        propagate_repo_parameters(clauses, aliases, parameters)
      end)

    Enum.flat_map(clauses, fn clause ->
      repo_variables = clause_repo_variables(clause, aliases, repo_parameters)

      context = %{
        aliases: aliases,
        imports: imports,
        literal_attributes: literal_attributes,
        proven_schema_parameters: proven_schema_parameters,
        repo_variables: repo_variables
      }

      {_body, calls} =
        clause.body
        |> normalize_pipeline_calls()
        |> Macro.prewalk([], fn node, calls ->
          {node, collect_opaque_insert_all_call(node, calls, clause, path, context)}
        end)

      Enum.reverse(calls)
    end)
  end

  defp collect_opaque_insert_all_call(node, calls, clause, path, context) do
    case persistence_write_call(
           node,
           context.aliases,
           context.imports,
           context.repo_variables
         ) do
      {:ok, kind, :insert_all, arguments, meta} ->
        target = persistence_target(kind, arguments)

        if statically_named_schema_target?(
             target,
             context.literal_attributes,
             clause,
             context.proven_schema_parameters
           ) do
          calls
        else
          [
            %{
              function: clause.identity,
              line: Keyword.get(meta, :line, clause.line),
              operation: :insert_all,
              path: path
            }
            | calls
          ]
        end

      _other ->
        calls
    end
  end

  defp statically_named_schema_target?({:__aliases__, _, _segments}, _attributes, _clause, _proven), do: true
  defp statically_named_schema_target?(target, _attributes, _clause, _proven) when is_binary(target), do: true

  defp statically_named_schema_target?(target, literal_attributes, clause, proven_schema_parameters) do
    match?({:ok, value} when is_binary(value), resolve_sql(target, literal_attributes, %{})) or
      proven_schema_parameter?(target, clause, proven_schema_parameters)
  end

  defp proven_literal_schema_parameters(clauses, literal_attributes) do
    fixed_point(MapSet.new(), fn proven ->
      Enum.reduce(clauses, proven, fn clause, next ->
        prove_literal_schema_parameters_for_clause(clause, clauses, literal_attributes, proven, next)
      end)
    end)
  end

  defp prove_literal_schema_parameters_for_clause(
         %{visibility: :defp} = clause,
         clauses,
         literal_attributes,
         proven,
         next
       ) do
    clause.params
    |> Enum.with_index()
    |> Enum.reduce(next, fn {_parameter, index}, current ->
      prove_literal_schema_parameter(clause, clauses, index, literal_attributes, proven, current)
    end)
  end

  defp prove_literal_schema_parameters_for_clause(_clause, _clauses, _attributes, _proven, next), do: next

  defp prove_literal_schema_parameter(clause, clauses, index, literal_attributes, proven, current) do
    callsites = local_parameter_callsites(clauses, clause, index)

    if callsites != [] and all_schema_callsites_attributed?(callsites, literal_attributes, proven),
      do: MapSet.put(current, {clause.id, index}),
      else: current
  end

  defp all_schema_callsites_attributed?(callsites, literal_attributes, proven) do
    Enum.all?(callsites, fn
      {:call, caller, argument} ->
        statically_named_schema_target?(argument, literal_attributes, caller, proven)

      :opaque ->
        false
    end)
  end

  defp local_parameter_callsites(clauses, target_clause, parameter_index) do
    calls = Enum.flat_map(clauses, &local_parameter_callsites_for_caller(&1, target_clause, parameter_index))
    captures = Enum.flat_map(clauses, &local_parameter_capture_for_caller(&1, target_clause))

    (calls ++ captures)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp local_parameter_callsites_for_caller(caller, target_clause, parameter_index) do
    {_body, found} =
      caller.body
      |> normalize_pipeline_calls()
      |> Macro.prewalk([], fn node, current ->
        {node, collect_local_parameter_call(node, current, caller, target_clause, parameter_index)}
      end)

    found
  end

  defp collect_local_parameter_call(node, current, caller, target_clause, parameter_index) do
    with {:ok, name, arguments} <- local_call(node),
         true <- name == target_clause.name,
         true <- MapSet.member?(target_clause.accepted_arities, length(arguments)) do
      case Enum.fetch(arguments, parameter_index) do
        {:ok, argument} -> [{:call, caller, argument} | current]
        :error -> [:opaque | current]
      end
    else
      _other -> current
    end
  end

  defp local_parameter_capture_for_caller(caller, target_clause) do
    {_body, found?} =
      Macro.prewalk(caller.body, false, fn node, current ->
        {node, current or local_function_capture?(node, target_clause)}
      end)

    if found?, do: [:opaque], else: []
  end

  defp local_function_capture?({:&, _, [{:/, _, [{name, _, context}, arity]}]}, target_clause)
       when is_atom(name) and is_atom(context) do
    name == target_clause.name and MapSet.member?(target_clause.accepted_arities, arity)
  end

  defp local_function_capture?(_node, _target_clause), do: false

  defp proven_schema_parameter?({name, _, context}, clause, proven_schema_parameters)
       when is_atom(name) and is_atom(context) do
    clause.params
    |> Enum.find_index(&MapSet.member?(variable_names(&1), name))
    |> case do
      nil -> false
      index -> MapSet.member?(proven_schema_parameters, {clause.id, index})
    end
  end

  defp proven_schema_parameter?(_target, _clause, _proven_schema_parameters), do: false

  defp opaque_dynamic_schema_writes_in_source(source, path) do
    if Regex.match?(@dynamic_schema_constructor_pattern, source),
      do: find_opaque_dynamic_schema_writes(source, path),
      else: []
  end

  defp find_opaque_dynamic_schema_writes(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    clauses = function_clauses(ast)
    literal_attributes = literal_binary_module_attributes(ast)
    proven_schema_parameters = proven_literal_schema_parameters(clauses, literal_attributes)

    opaque_schema_returns =
      opaque_dynamic_schema_returning_clauses(
        clauses,
        literal_attributes,
        proven_schema_parameters
      )

    repo_parameters =
      fixed_point(MapSet.new(), fn parameters ->
        propagate_repo_parameters(clauses, aliases, parameters)
      end)

    base_context = %{
      aliases: aliases,
      clauses: clauses,
      imports: imports,
      literal_attributes: literal_attributes,
      opaque_schema_returns: opaque_schema_returns,
      path: path,
      proven_schema_parameters: proven_schema_parameters
    }

    Enum.flat_map(clauses, fn clause ->
      context =
        base_context
        |> Map.put(:clause, clause)
        |> Map.put(:repo_variables, clause_repo_variables(clause, aliases, repo_parameters))

      opaque_dynamic_schema_writes_in_clause(context)
    end)
  end

  defp opaque_dynamic_schema_writes_in_clause(context) do
    {_body, writes} =
      context.clause.body
      |> normalize_pipeline_calls()
      |> Macro.prewalk([], fn node, current ->
        {node, collect_opaque_dynamic_schema_write(node, current, context)}
      end)

    writes |> Enum.reverse() |> Enum.uniq()
  end

  defp collect_opaque_dynamic_schema_write(node, current, context) do
    case persistence_write_call(node, context.aliases, context.imports, context.repo_variables) do
      {:ok, kind, operation, arguments, meta} ->
        target = persistence_target(kind, arguments)

        if opaque_dynamic_schema_target?(
             target,
             context.literal_attributes,
             context.clause,
             context.proven_schema_parameters,
             context.opaque_schema_returns,
             context.clauses
           ) do
          violation = %{
            function: context.clause.identity,
            line: Keyword.get(meta, :line, context.clause.line),
            operation: operation,
            path: context.path
          }

          [violation | current]
        else
          current
        end

      :not_a_write ->
        current
    end
  end

  defp opaque_dynamic_schema_returning_clauses(clauses, literal_attributes, proven_schema_parameters) do
    direct_returns =
      Enum.reduce(clauses, MapSet.new(), fn clause, current ->
        if clause_contains_opaque_dynamic_constructor?(
             clause,
             literal_attributes,
             proven_schema_parameters
           ),
           do: MapSet.put(current, clause.id),
           else: current
      end)

    if MapSet.size(direct_returns) == 0 do
      direct_returns
    else
      clause_call_index = local_clause_call_index(clauses)
      return_calls = Map.new(clauses, &{&1.id, local_return_call_ids(&1, clause_call_index)})

      fixed_point(direct_returns, &propagate_opaque_return_calls(return_calls, &1))
    end
  end

  defp propagate_opaque_return_calls(return_calls, current) do
    Enum.reduce(return_calls, current, fn {caller_id, callee_ids}, next ->
      if Enum.any?(callee_ids, &MapSet.member?(current, &1)),
        do: MapSet.put(next, caller_id),
        else: next
    end)
  end

  defp clause_contains_opaque_dynamic_constructor?(clause, literal_attributes, proven_schema_parameters) do
    clause.body
    |> normalize_pipeline_calls()
    |> opaque_dynamic_schema_constructor?(literal_attributes, clause, proven_schema_parameters)
  end

  defp local_clause_call_index(clauses) do
    Enum.reduce(clauses, %{}, fn clause, index ->
      Enum.reduce(clause.accepted_arities, index, fn arity, current ->
        Map.update(current, {clause.name, arity}, MapSet.new([clause.id]), &MapSet.put(&1, clause.id))
      end)
    end)
  end

  defp local_return_call_ids(clause, clause_call_index) do
    clause.body
    |> normalize_pipeline_calls()
    |> return_expressions()
    |> Enum.reduce(MapSet.new(), fn expression, current ->
      {_expression, called_ids} =
        Macro.prewalk(
          expression,
          current,
          &collect_local_return_call(&1, &2, clause_call_index)
        )

      called_ids
    end)
  end

  defp collect_local_return_call(node, found, clause_call_index) do
    ids =
      case local_call(node) do
        {:ok, name, arguments} ->
          Map.get(clause_call_index, {name, length(arguments)}, MapSet.new())

        :not_a_local_call ->
          MapSet.new()
      end

    {node, MapSet.union(found, ids)}
  end

  defp opaque_dynamic_schema_target?(
         target,
         literal_attributes,
         clause,
         proven_schema_parameters,
         opaque_schema_returns,
         clauses
       ) do
    opaque_dynamic_schema_constructor?(
      target,
      literal_attributes,
      clause,
      proven_schema_parameters
    ) or
      local_call_returns_opaque_schema?(target, opaque_schema_returns, clauses)
  end

  defp local_call_returns_opaque_schema?(target, opaque_schema_returns, clauses) do
    {_target, opaque?} =
      Macro.prewalk(target, false, fn node, current ->
        opaque_call? =
          case local_call(node) do
            {:ok, name, arguments} ->
              clauses
              |> matching_clauses(name, length(arguments))
              |> Enum.any?(&MapSet.member?(opaque_schema_returns, &1.id))

            :not_a_local_call ->
              false
          end

        {node, current or opaque_call?}
      end)

    opaque?
  end

  defp opaque_dynamic_schema_constructor?(target, literal_attributes, clause, proven_schema_parameters) do
    {_target, opaque?} =
      Macro.prewalk(target, false, fn
        {constructor, _, [schema | _arguments]} = node, current when constructor in [:struct, :struct!] ->
          attributed? =
            statically_named_schema_target?(
              schema,
              literal_attributes,
              clause,
              proven_schema_parameters
            )

          {node, current or not attributed?}

        node, current ->
          {node, current}
      end)

    opaque?
  end

  defp assert_opaque_insert_all_targets_attributed!(calls, writes) do
    attributed =
      MapSet.new(writes, &{&1.path, &1.function, &1.line, &1.operation})

    opaque =
      Enum.reject(calls, fn call ->
        MapSet.member?(attributed, {call.path, call.function, call.line, call.operation})
      end)

    assert opaque == [], """
    An opaque insert_all target is not attributable to any concrete persistence
    target. Keep schema selection visible through local literal-schema callers,
    or use a literal reviewed table name; sealed helpers must inventory their
    exact business call sites.

    Opaque calls: #{inspect(opaque, pretty: true, limit: :infinity)}
    """
  end

  defp transparent_delegate_functions_imported?(module, options) do
    functions =
      @transparent_write_delegates
      |> Enum.filter(&(&1.module == module))
      |> MapSet.new(&{&1.function, &1.arity})

    import_options = List.first(options) || []
    only = Keyword.get(import_options, :only)
    except = Keyword.get(import_options, :except, [])

    cond do
      is_list(only) ->
        Enum.any?(only, &MapSet.member?(functions, &1))

      is_list(except) ->
        Enum.any?(functions, &(&1 not in except))

      true ->
        true
    end
  end

  defp assert_transparent_delegate_calls_attributed!(calls, writes) do
    attributed =
      MapSet.new(writes, &{&1.path, &1.function, &1.line, &1.operation})

    opaque =
      Enum.reject(calls, fn call ->
        call.repo_attributed? and call.schema_attributed? and
          MapSet.member?(attributed, {call.path, call.function, call.line, call.operation})
      end)

    assert opaque == [], """
    An opaque transparent write delegate call has no statically attributable
    Repo/schema target. Keep the concrete schema visible at the business call
    site or propagate it through a local, statically resolved helper.

    Opaque calls: #{inspect(opaque, pretty: true, limit: :infinity)}
    """
  end

  defp unresolved_variable_repo_writes(path, delegates) do
    source = File.read!(path)
    unresolved_variable_repo_writes_in_source(source, path, delegates)
  end

  defp unresolved_variable_repo_writes_in_source(source, path, delegates) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    clauses = function_clauses(ast)
    attributes = binary_module_attributes(ast)

    repo_parameters =
      fixed_point(MapSet.new(), fn parameters ->
        propagate_repo_parameters(clauses, aliases, parameters)
      end)

    Enum.flat_map(clauses, fn clause ->
      repo_variables = clause_repo_variables(clause, aliases, repo_parameters)
      sql_bindings = resolved_sql_variables(clause.body, attributes, variable_names(clause.params))

      writes =
        variable_receiver_writes(clause) ++
          variable_receiver_raw_sql_writes(clause, attributes, sql_bindings)

      writes
      |> Enum.reject(fn write ->
        (clause.visibility == :defp and write.operation != :unresolved_raw_sql and
           MapSet.member?(repo_variables, write.receiver)) or
          transparent_delegate_definition?(delegates, path, clause, write)
      end)
      |> Enum.map(fn write ->
        %{
          path: path,
          function: clause.identity,
          operation: write.operation,
          receiver: write.receiver,
          line: write.line
        }
      end)
    end)
  end

  defp variable_receiver_writes(clause) do
    {_body, writes} =
      Macro.prewalk(clause.body, [], fn
        {:|>, pipe_meta, [left, {{:., _, [{name, _, context}, operation]}, call_meta, arguments}]} = node, writes
        when is_atom(name) and is_atom(context) and operation in @repo_write_functions and
               is_list(arguments) ->
          write = %{
            arguments: [left | arguments],
            clause: clause,
            clause_id: clause.id,
            line: Keyword.get(call_meta, :line, Keyword.get(pipe_meta, :line, clause.line)),
            operation: operation,
            receiver: name
          }

          {node, [write | writes]}

        {{:., _, [{name, _, context}, operation]}, meta, arguments} = node, writes
        when is_atom(name) and is_atom(context) and operation in @repo_write_functions and
               is_list(arguments) and arguments != [] ->
          write = %{
            arguments: arguments,
            clause: clause,
            clause_id: clause.id,
            line: Keyword.get(meta, :line, clause.line),
            operation: operation,
            receiver: name
          }

          {node, [write | writes]}

        node, writes ->
          {node, writes}
      end)

    Enum.reverse(writes)
  end

  defp variable_receiver_raw_sql_writes(clause, attributes, sql_bindings) do
    {_body, writes} =
      clause.body
      |> normalize_pipeline_calls()
      |> Macro.prewalk([], fn
        {{:., _, [{name, _, context}, operation]}, meta, [sql_ast | _arguments]} = node, writes
        when is_atom(name) and is_atom(context) and operation in @repo_raw_sql_functions ->
          operation =
            case resolve_sql(sql_ast, attributes, sql_bindings) do
              {:ok, sql} -> raw_sql_mutation_operation(sql)
              :error -> :unresolved_raw_sql
            end

          if operation do
            write = %{
              arguments: [sql_ast],
              clause: clause,
              clause_id: clause.id,
              line: Keyword.get(meta, :line, clause.line),
              operation: operation,
              receiver: name
            }

            {node, [write | writes]}
          else
            {node, writes}
          end

        node, writes ->
          {node, writes}
      end)

    Enum.reverse(writes)
  end

  defp raw_sql_mutation_operation(sql) do
    sql =
      sql
      |> String.replace(~r|/\*.*?\*/|s, " ")
      |> String.replace(~r/--[^\n]*/, " ")

    Enum.find_value(
      [
        {:insert, ~r/(?:\A|[;()])\s*insert\s+into\b/i},
        {:delete, ~r/(?:\A|[;()])\s*delete\s+from\b/i},
        {:update, ~r/(?:\A|[;()])\s*update\s+/i},
        {:insert, ~r/(?:\A|[;()])\s*merge\s+into\b/i},
        {:delete_all, ~r/(?:\A|[;()])\s*truncate\s+(?:table\s+)?/i}
      ],
      fn {operation, pattern} -> if Regex.match?(pattern, sql), do: operation end
    )
  end

  defp unresolved_raw_sql_calls_in_source(source, path) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    attributes = binary_module_attributes(ast)

    ast
    |> function_clauses()
    |> Enum.flat_map(fn clause ->
      unresolved_raw_sql_calls_in_clause(clause, path, aliases, imports, attributes)
    end)
  end

  defp unresolved_raw_sql_calls_in_clause(clause, path, aliases, imports, attributes) do
    sql_bindings = resolved_sql_variables(clause.body, attributes, variable_names(clause.params))
    context = %{aliases: aliases, attributes: attributes, imports: imports, path: path, sql_bindings: sql_bindings}

    {_body, calls} =
      clause.body
      |> normalize_pipeline_calls()
      |> Macro.prewalk([], fn node, current ->
        {node, collect_unresolved_raw_sql_call(node, current, clause, context)}
      end)

    calls |> Enum.reverse() |> Enum.uniq()
  end

  defp collect_unresolved_raw_sql_call(node, current, clause, context) do
    with {:ok, sql_ast, meta} <- raw_sql_call(node, context.aliases, context.imports),
         :error <- resolve_sql(sql_ast, context.attributes, context.sql_bindings) do
      call = %{
        function: clause.identity,
        line: Keyword.get(meta, :line, clause.line),
        path: context.path
      }

      [call | current]
    else
      _resolved_or_not_raw_sql -> current
    end
  end

  defp transparent_delegate_definition?(delegates, path, clause, write) do
    Enum.any?(delegates, fn delegate ->
      delegate.path == path and delegate.function == clause.name and delegate.arity == clause.arity and
        delegate.operation == write.operation and
        parameter_name!(clause, delegate.repo_argument) == write.receiver and
        parameter_name!(clause, delegate.schema_argument) == variable_name(Enum.at(write.arguments, 0))
    end)
  end

  defp parameter_name!(clause, index) do
    clause.params
    |> Enum.at(index)
    |> variable_name()
    |> case do
      nil -> flunk("expected a variable parameter at index #{index} in #{clause.identity}")
      name -> name
    end
  end

  defp variable_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp variable_name(_ast), do: nil

  defp full_persistence_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> Map.fetch!(:persistence_ownership)
  end

  defp shared_mapping_inventory(root, bounded_contexts, passive_mapping_roots) do
    root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&shared_mappings_in_file(&1, bounded_contexts, passive_mapping_roots))
  end

  defp shared_mappings_in_file(path, bounded_contexts, passive_mapping_roots) do
    path
    |> File.read!()
    |> shared_mappings_in_source(path, bounded_contexts, passive_mapping_roots)
  end

  defp shared_mappings_in_source(source, path, bounded_contexts, passive_mapping_roots) do
    ast = quoted!(source, path)

    {_ast, mappings} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _, segments}, [do: body]]} = node, mappings ->
          mapping =
            case shared_schema_table(body, path) do
              nil ->
                []

              table ->
                {context, owner_eligible?} =
                  shared_context_for_path(path, bounded_contexts, passive_mapping_roots)

                [
                  shared_mapping(
                    table,
                    context,
                    shared_role_for_path(path),
                    Enum.join(segments, "."),
                    path,
                    owner_eligible?
                  )
                ]
            end

          {node, mapping ++ mappings}

        node, mappings ->
          {node, mappings}
      end)

    Enum.reverse(mappings)
  end

  defp shared_schema_table(ast, path) do
    {_ast, schemas} =
      Macro.prewalk(ast, [], fn
        {:schema, _meta, [table | _rest]} = node, tables when is_binary(table) ->
          {node, [{:literal, table} | tables]}

        {:schema, _meta, [_table | _rest]} = node, tables ->
          {node, [:non_literal | tables]}

        node, tables ->
          {node, tables}
      end)

    case Enum.uniq(schemas) do
      [] ->
        nil

      [{:literal, table}] ->
        table

      schemas ->
        if :non_literal in schemas,
          do: flunk("non-literal Ecto schema in #{path}"),
          else: flunk("one module maps multiple SQL tables in #{path}: #{inspect(schemas)}")
    end
  end

  defp schema_declarations(source, path) do
    {_ast, declarations} =
      source
      |> quoted!(path)
      |> Macro.prewalk([], fn
        {:schema, _meta, [table | _rest]} = node, declarations when is_binary(table) ->
          {node, [%{table: table} | declarations]}

        {:schema, _meta, [_table | _rest]} = node, declarations ->
          {node, [%{table: :non_literal} | declarations]}

        node, declarations ->
          {node, declarations}
      end)

    declarations |> Enum.reverse() |> Enum.uniq()
  end

  defp shared_context_for_path(path, bounded_contexts, passive_mapping_roots) do
    case Path.split(path) do
      ["lib", "storyarn", context | _rest] ->
        shared_context_for_root(context, path, bounded_contexts, passive_mapping_roots)

      _other ->
        flunk("Ecto mapping is outside a bounded context: #{path}")
    end
  end

  defp shared_context_for_root(context, path, bounded_contexts, passive_mapping_roots) do
    bounded_context = Enum.find(bounded_contexts, &(Atom.to_string(&1) == context))

    cond do
      bounded_context -> {bounded_context, true}
      context in passive_mapping_roots -> {:technical_consumer, false}
      true -> flunk("Ecto mapping is outside the declared bounded contexts: #{path}")
    end
  end

  defp shared_role_for_path(path) do
    path
    |> Path.split()
    |> Enum.find_value(:other, fn
      "entities" -> :entities
      "projections" -> :projections
      "records" -> :records
      _segment -> nil
    end)
  end

  defp shared_mappings(inventory) do
    inventory
    |> Enum.group_by(& &1.table)
    |> Map.filter(fn {_table, mappings} ->
      mappings |> Enum.map(& &1.context) |> Enum.uniq() |> length() > 1
    end)
  end

  defp classify_shared_mappings(shared, policy, persistence) do
    {classifications, errors} =
      shared
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({%{}, []}, &classify_shared_table(&1, &2, policy, persistence))

    case Enum.reverse(errors) do
      [] -> {:ok, classifications}
      errors -> {:error, errors}
    end
  end

  defp classify_shared_table({table, mappings}, {classified, errors}, policy, persistence) do
    case shared_table_authority(table, mappings, policy, persistence) do
      {:ok, owners, write_mode} ->
        classification = shared_table_classification(mappings, owners, write_mode, policy, persistence)
        {Map.put(classified, table, classification), errors}

      {:error, reason} ->
        {classified, [{table, reason} | errors]}
    end
  end

  defp shared_table_classification(mappings, owners, write_mode, policy, persistence) do
    classified_mappings =
      Enum.map(mappings, fn mapping ->
        classification = shared_mapping_classification(mapping, owners, write_mode, policy, persistence)
        Map.put(mapping, :classification, classification)
      end)

    %{owner_contexts: owners, write_mode: write_mode, mappings: classified_mappings}
  end

  defp shared_table_authority(table, mappings, policy, persistence) do
    persistence_contract =
      Enum.find_value(persistence, fn {name, contract} ->
        if Atom.to_string(name) == table, do: contract
      end)

    override =
      Enum.find_value(policy.owner_context_overrides, fn {name, override} ->
        if Atom.to_string(name) == table, do: override
      end)

    case {persistence_contract, override} do
      {contract, _override} when not is_nil(contract) ->
        {:ok, shared_ordinary_contexts(contract), :dedicated_contract}

      {nil, override} when not is_nil(override) ->
        {:ok, Enum.sort(override.owner_contexts), override.application_write_mode}

      {nil, nil} ->
        inferred_shared_table_authority(mappings)
    end
  end

  defp inferred_shared_table_authority(mappings) do
    owners =
      mappings
      |> Enum.filter(&(&1.role == :entities and &1.owner_eligible?))
      |> Enum.map(& &1.context)
      |> Enum.uniq()
      |> Enum.sort()

    case owners do
      [] -> {:error, :missing_owner}
      [_owner] -> {:ok, owners, :owner_context}
      owners -> {:error, {:ambiguous_owner, owners}}
    end
  end

  defp shared_ordinary_contexts(contract) do
    direct =
      [Map.get(contract, :ordinary_owner)] ++
        Enum.map(Map.get(contract, :ordinary_writers, []), &Map.get(&1, :context)) ++
        Map.values(Map.get(contract, :source_owners, %{}))

    direct
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp shared_mapping_classification(mapping, owner_contexts, write_mode, policy, persistence) do
    cond do
      write_mode == :no_application_writes -> :passive
      mapping.context in owner_contexts and write_mode in [:dedicated_contract, :exact_inventory] -> :owner_exact
      mapping.context in owner_contexts -> :owner_writable
      shared_privileged_mapping?(mapping, policy, persistence) -> :privileged
      true -> :passive
    end
  end

  defp shared_privileged_mapping?(mapping, policy, persistence) do
    writers =
      policy.exact_writers ++
        policy.privileged_writers ++ shared_sensitive_privileged_writers_for_mapping(persistence)

    Enum.any?(writers, fn writer ->
      Atom.to_string(writer.table) == mapping.table and writer.context == mapping.context and
        mapping.path in writer.mapping_paths
    end)
  end

  defp shared_sensitive_privileged_writers_for_mapping(persistence) do
    Enum.flat_map(persistence, fn {table, contract} ->
      Enum.map(shared_sensitive_privileged_writers(contract), fn writer ->
        Map.put(writer, :table, table)
      end)
    end)
  end

  defp shared_table_writes(shared, policy) do
    sources =
      policy.write_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Map.new(fn path ->
        source = File.read!(path)
        attributes = source |> quoted!(path) |> binary_module_attributes() |> Map.values()
        {path, {source, attributes}}
      end)

    Map.new(shared, fn {table, mappings} ->
      modules = Enum.map(mappings, & &1.module)
      markers = [table | modules ++ Enum.map(modules, &(&1 |> String.split(".") |> List.last()))]

      writes =
        sources
        |> Enum.flat_map(
          &shared_source_writes(
            &1,
            markers,
            modules,
            table,
            policy.reviewed_dynamic_writers,
            policy.bounded_contexts
          )
        )
        |> Enum.uniq_by(&{&1.path, &1.function, &1.operation})
        |> Enum.sort_by(&{&1.path, &1.function, &1.operation})

      {table, writes}
    end)
  end

  defp shared_source_candidate?(source, markers),
    do: String.contains?(source, markers) or String.contains?(source, "assoc(")

  defp shared_source_candidate?(source, markers, attribute_values, table),
    do: shared_source_candidate?(source, markers) or table in attribute_values

  defp shared_source_writes(
         {path, {source, attribute_values}},
         markers,
         modules,
         table,
         dynamic_writers,
         bounded_contexts
       ) do
    if shared_source_candidate?(source, markers, attribute_values, table),
      do: shared_detected_table_writes(source, path, modules, table, dynamic_writers, bounded_contexts),
      else: []
  end

  defp shared_detected_table_writes(source, path, modules, table, dynamic_writers, bounded_contexts) do
    {static_writes, unresolved} = table_mutation_analysis(source, path, modules, table)
    dynamic = shared_dynamic_writer(dynamic_writers, path, table)

    dynamic_writes =
      case {unresolved, dynamic} do
        {[], _dynamic} ->
          []

        {unresolved, nil} ->
          flunk("unreviewed unresolved raw SQL while auditing #{table}: #{inspect(unresolved, pretty: true)}")

        {unresolved, dynamic} ->
          unresolved_functions = unresolved |> Enum.map(& &1.function) |> Enum.uniq() |> Enum.sort()

          assert unresolved_functions == [dynamic.function]
          assert dynamic.function in source_function_identities(source, path)

          [
            %{
              path: path,
              function: dynamic.function,
              operation: dynamic.operation,
              line: Enum.min_by(unresolved, & &1.line).line
            }
          ]
      end

    writes = static_writes ++ dynamic_writes

    Enum.map(writes, fn write ->
      write
      |> Map.put(:table, table)
      |> Map.put(:context, shared_context_for_write_path(write.path, bounded_contexts))
    end)
  end

  defp shared_dynamic_writer(writers, path, table) do
    Enum.find(writers, fn writer ->
      writer.path == path and table in Enum.map(writer.tables, &Atom.to_string/1)
    end)
  end

  defp shared_context_for_write_path(path, bounded_contexts) do
    case Path.split(path) do
      ["lib", "storyarn", context | _rest] ->
        Enum.find(bounded_contexts, &(Atom.to_string(&1) == context)) || :infrastructure

      ["lib", "storyarn_web" | _rest] ->
        :presentation_adapters

      ["lib", "mix", "tasks" | _rest] ->
        :infrastructure

      _other ->
        :infrastructure
    end
  end

  defp allowed_shared_exact_writes(policy) do
    policy.exact_writers
    |> Kernel.++(policy.privileged_writers)
    |> Enum.flat_map(&shared_declared_writer_identities/1)
    |> MapSet.new()
  end

  defp shared_sensitive_privileged_writers(%{privileged_writers: writers}) when is_list(writers), do: writers

  defp shared_sensitive_privileged_writers(%{privileged_project_writers: groups}) do
    Enum.flat_map(groups, fn {_name, group} ->
      Enum.map(group.writers, fn writer ->
        %{
          context: :projects,
          path: writer.path,
          mapping_paths: writer.mapping_paths,
          functions: writer.functions
        }
      end)
    end)
  end

  defp shared_sensitive_privileged_writers(_contract), do: []

  defp shared_declared_writer_identities(writer) do
    Enum.flat_map(writer.functions, fn
      %{identity: identity, operations: operations} ->
        Enum.map(operations, &{Atom.to_string(writer.table), writer.path, identity, &1})

      identity when is_binary(identity) ->
        flunk("writer function lacks operations: #{writer.path} #{identity}")
    end)
  end

  defp reviewed_shared_false_positives(policy) do
    MapSet.new(policy.scanner_false_positives, fn candidate ->
      {Atom.to_string(candidate.table), candidate.path, candidate.function, candidate.operation}
    end)
  end

  defp shared_write_allowed?(classification, write, identity, allowed_writes, dedicated_allowances) do
    case classification.write_mode do
      :owner_context ->
        write.context in classification.owner_contexts or MapSet.member?(allowed_writes, identity)

      :exact_inventory ->
        MapSet.member?(allowed_writes, identity)

      :dedicated_contract ->
        dedicated_contract_write_allowed?(identity, dedicated_allowances)

      :no_application_writes ->
        false
    end
  end

  defp dedicated_contract_write_allowed?(identity, allowances), do: MapSet.member?(allowances.exact, identity)

  defp assert_exact_dedicated_contract_inventory!(table, actual_writes, allowances) do
    actual =
      actual_writes
      |> Map.fetch!(table)
      |> MapSet.new(&shared_write_identity(table, &1))

    declared =
      allowances.exact
      |> Enum.filter(&(elem(&1, 0) == table))
      |> MapSet.new()

    assert actual == declared, """
    #{table} must declare every writer and no extra path/function/operation
    allowance. A stale operation would silently widen future authority.

    Actual: #{actual |> MapSet.to_list() |> Enum.sort() |> inspect(pretty: true)}
    Declared: #{declared |> MapSet.to_list() |> Enum.sort() |> inspect(pretty: true)}
    """
  end

  defp dedicated_contract_allowances(persistence) do
    exact =
      Enum.reduce(persistence, MapSet.new(), fn {table, contract}, identities ->
        table = Atom.to_string(table)

        contract_identities =
          cond do
            Map.has_key?(contract, :writers) ->
              aggregate_contract_identities(table, contract)

            Map.has_key?(contract, :ordinary_writers) and Map.has_key?(contract, :privileged_writers) ->
              declared_contract_identities(table, contract)

            Map.has_key?(contract, :ordinary_writers) and
                Map.has_key?(contract, :privileged_project_writers) ->
              project_language_contract_identities(table, contract)

            true ->
              MapSet.new()
          end

        MapSet.union(identities, contract_identities)
      end)

    %{exact: exact}
  end

  defp aggregate_contract_identities(table, contract) do
    writer_identities =
      Enum.flat_map(contract.writers, fn writer ->
        Enum.flat_map(writer.functions, fn function ->
          Enum.map(function.operations, &{table, writer.path, function.identity, &1})
        end)
      end)

    false_positive_identities =
      Enum.map(Map.get(contract, :scanner_false_positives, []), fn candidate ->
        {table, candidate.path, candidate.function, candidate.operation}
      end)

    MapSet.new(writer_identities ++ false_positive_identities)
  end

  defp declared_contract_identities(table, contract) do
    contract.ordinary_writers
    |> Kernel.++(contract.privileged_writers)
    |> Enum.flat_map(fn writer ->
      Enum.flat_map(writer.functions, fn function ->
        Enum.map(function.operations, &{table, writer.path, function.identity, &1})
      end)
    end)
    |> MapSet.new()
  end

  defp project_language_contract_identities(table, contract) do
    privileged_writers =
      contract.privileged_project_writers
      |> Map.values()
      |> Enum.flat_map(& &1.writers)

    (contract.ordinary_writers ++ privileged_writers)
    |> Enum.flat_map(fn writer ->
      Enum.flat_map(writer.functions, fn function ->
        Enum.map(function.operations, &{table, writer.path, function.identity, &1})
      end)
    end)
    |> MapSet.new()
  end

  defp assert_shared_mapping_policy!(shared, classifications, actual_writes, policy, persistence) do
    dedicated_tables =
      (@reference_tables ++ @owned_inventory_tables ++ @aggregate_identity_tables ++ [:project_languages])
      |> Enum.uniq()
      |> Enum.sort()

    assert_dedicated_shared_tables!(dedicated_tables, classifications, persistence)
    assert_shared_policy_shape!(shared, policy)
    actual_identities = shared_actual_identities(actual_writes)
    assert_configured_shared_writers!(shared, classifications, actual_identities, policy)
    assert_sensitive_shared_writers!(shared, persistence, policy)
    assert_privileged_workflows!(policy)
    assert_reviewed_dynamic_writers!(policy.reviewed_dynamic_writers, shared, actual_identities, policy)
    assert_reviewed_shared_false_positives!(policy.scanner_false_positives, actual_identities, policy)
    assert_entity_version_scope!(policy.exact_writers)
    assert_trigger_owned_receipts!(actual_writes)
  end

  defp assert_dedicated_shared_tables!(dedicated_tables, classifications, persistence) do
    assert persistence |> Map.keys() |> Enum.sort() == dedicated_tables

    for table <- dedicated_tables do
      assert Map.fetch!(classifications, Atom.to_string(table)).write_mode == :dedicated_contract
    end
  end

  defp assert_shared_policy_shape!(shared, policy) do
    assert policy.passive_mapping_roots == ["architecture", "public", "workers"]
    assert policy.passive_mapping_roots == Enum.sort(policy.passive_mapping_roots)

    assert policy.owner_context_overrides |> Map.keys() |> Enum.sort() == [
             :entity_versions,
             :storage_cleanup_ownership_receipts
           ]

    for {table, override} <- policy.owner_context_overrides do
      assert_shared_owner_override!(table, override, shared, policy.bounded_contexts)
    end
  end

  defp assert_shared_owner_override!(table, override, shared, bounded_contexts) do
    mappings = Map.fetch!(shared, Atom.to_string(table))
    assert is_binary(override.reason) and override.reason != ""
    assert override.owner_contexts == override.owner_contexts |> Enum.uniq() |> Enum.sort()
    assert Enum.all?(override.owner_contexts, &(&1 in bounded_contexts))
    assert override.application_write_mode in [:exact_inventory, :no_application_writes]

    for owner_context <- override.owner_contexts do
      assert Enum.any?(mappings, &(&1.context == owner_context)),
             "#{owner_context} no longer maps overridden shared table #{table}"
    end
  end

  defp shared_actual_identities(actual_writes) do
    actual_writes
    |> Enum.flat_map(fn {table, writes} -> Enum.map(writes, &shared_write_identity(table, &1)) end)
    |> MapSet.new()
  end

  defp assert_configured_shared_writers!(shared, classifications, actual_identities, policy) do
    configured_writers = policy.exact_writers ++ policy.privileged_writers
    configured_identities = Enum.flat_map(configured_writers, &shared_declared_writer_identities/1)

    assert configured_identities == Enum.uniq(configured_identities),
           "shared writer identities must be declared exactly once"

    for writer <- configured_writers do
      assert_shared_writer!(writer, shared, classifications, actual_identities, policy)
    end
  end

  defp assert_sensitive_shared_writers!(shared, persistence, policy) do
    for writer <- shared_sensitive_privileged_writers_for_mapping(persistence) do
      assert File.regular?(writer.path)
      assert writer.context in policy.bounded_contexts
      assert writer.mapping_paths != []
      assert writer.mapping_paths == writer.mapping_paths |> Enum.uniq() |> Enum.sort()
      assert_shared_writer_mappings!(writer.table, writer.context, writer.mapping_paths, shared)
    end
  end

  defp assert_privileged_workflows!(policy) do
    workflow_keys = policy.privileged_workflows |> Map.keys() |> Enum.sort()
    used_workflows = policy.privileged_writers |> Enum.map(& &1.authority) |> Enum.uniq() |> Enum.sort()
    assert workflow_keys == used_workflows

    for {_name, workflow} <- policy.privileged_workflows do
      assert is_binary(workflow.transaction) and workflow.transaction != ""
      assert is_binary(workflow.locks_or_preconditions) and workflow.locks_or_preconditions != ""
    end
  end

  defp assert_trigger_owned_receipts!(actual_writes) do
    receipt_writes = Map.fetch!(actual_writes, "storage_cleanup_ownership_receipts")
    assert receipt_writes == [], "database-trigger-owned cleanup receipts cannot acquire an application writer"
  end

  defp assert_shared_writer!(writer, shared, classifications, actual_identities, policy) do
    table = Atom.to_string(writer.table)

    assert Map.has_key?(shared, table)
    assert File.regular?(writer.path), "declared shared writer is missing: #{writer.path}"
    assert shared_context_for_write_path(writer.path, policy.bounded_contexts) == writer.context
    assert is_atom(writer.authority)
    assert is_binary(writer.reason) and writer.reason != ""
    assert writer.mapping_paths != []
    assert writer.mapping_paths == writer.mapping_paths |> Enum.uniq() |> Enum.sort()
    assert valid_declared_functions?(writer.functions)

    assert_shared_writer_mappings!(writer.table, writer.context, writer.mapping_paths, shared)

    source = File.read!(writer.path)
    available_functions = source_function_identities(source, writer.path)

    for function <- writer.functions do
      assert function.identity in available_functions
    end

    for identity <- shared_declared_writer_identities(writer) do
      assert MapSet.member?(actual_identities, identity),
             "stale or undetected shared writer exception: #{inspect(identity)}"
    end

    classification = Map.fetch!(classifications, table)

    if writer in policy.privileged_writers do
      refute writer.context in classification.owner_contexts
      assert Map.has_key?(policy.privileged_workflows, writer.authority)
    else
      assert classification.write_mode == :exact_inventory
    end
  end

  defp assert_shared_writer_mappings!(table, context, mapping_paths, shared) do
    table = Atom.to_string(table)
    mappings = Map.fetch!(shared, table)

    for mapping_path <- mapping_paths do
      assert File.regular?(mapping_path), "declared shared mapping is missing: #{mapping_path}"

      assert Enum.any?(mappings, fn mapping ->
               mapping.path == mapping_path and mapping.context == context and mapping.table == table
             end),
             "#{mapping_path} does not map #{table} for #{context}"
    end
  end

  defp assert_reviewed_dynamic_writers!(writers, shared, actual_identities, policy) do
    assert writers != []

    for writer <- writers do
      assert File.regular?(writer.path)
      assert shared_context_for_write_path(writer.path, policy.bounded_contexts) == writer.context
      assert is_binary(writer.reason) and writer.reason != ""
      assert writer.tables != []
      assert writer.tables == writer.tables |> Enum.uniq() |> Enum.sort()
      assert writer.function in source_function_identities(File.read!(writer.path), writer.path)

      source = File.read!(writer.path)
      function_source = source_for_function_identities(source, writer.path, [writer.function])

      assert source |> quoted!(writer.path) |> Macro.to_string() |> sha256() == writer.module_sha256,
             "#{writer.path} changed; re-audit its dynamic table validation and SQL target"

      assert literal_word_list_attribute(source, writer.path, :allowed_tables) ==
               Enum.map(writer.tables, &Atom.to_string/1)

      for table <- writer.tables do
        table_name = Atom.to_string(table)
        assert Map.has_key?(shared, table_name)

        {_static_writes, unresolved} =
          table_mutation_analysis(
            source,
            writer.path,
            Enum.map(Map.fetch!(shared, table_name), & &1.module),
            table_name
          )

        assert unresolved |> Enum.map(& &1.function) |> Enum.uniq() == [writer.function]

        assert MapSet.member?(
                 actual_identities,
                 {table_name, writer.path, writer.function, writer.operation}
               )
      end

      assert function_source =~ "@allowed_tables"
      assert function_source =~ "validated_identifier!"
      assert dynamic_sql_operation(function_source) == writer.operation
    end
  end

  defp dynamic_sql_operation(function_source) do
    operations =
      ~r/\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\b/i
      |> Regex.scan(function_source, capture: :first)
      |> Enum.map(fn [operation] ->
        case operation |> String.upcase() |> String.split() |> hd() do
          "INSERT" -> :insert
          "UPDATE" -> :update
          "DELETE" -> :delete
        end
      end)
      |> Enum.uniq()

    case operations do
      [operation] -> operation
      _other -> flunk("dynamic SQL writer must expose exactly one literal mutation verb")
    end
  end

  defp assert_reviewed_shared_false_positives!(false_positives, actual_identities, policy) do
    identities =
      Enum.map(false_positives, fn candidate ->
        assert File.regular?(candidate.path)
        assert shared_context_for_write_path(candidate.path, policy.bounded_contexts) == candidate.context
        assert is_binary(candidate.reason) and candidate.reason != ""
        source = File.read!(candidate.path)
        assert candidate.function in source_function_identities(source, candidate.path)

        assert source
               |> source_for_function_identities(candidate.path, [candidate.function])
               |> sha256() == candidate.source_sha256,
               "#{candidate.path} #{candidate.function} changed; re-audit the conservative scanner exception"

        identity =
          {Atom.to_string(candidate.table), candidate.path, candidate.function, candidate.operation}

        assert MapSet.member?(actual_identities, identity)
        identity
      end)

    assert identities == Enum.uniq(identities)
  end

  defp assert_entity_version_scope!(writers) do
    writers = Enum.filter(writers, &(&1.table == :entity_versions))
    assert writers != []

    for writer <- writers do
      assert_entity_version_writer_scope!(writer)
    end
  end

  defp assert_entity_version_writer_scope!(writer) do
    assert writer.entity_type in ["flow", "scene", "sheet"]
    source = File.read!(writer.path)
    assert_tool_entity_version_scope!(writer, source)
    assert_entity_version_delete_scope!(writer, source)
  end

  defp assert_tool_entity_version_scope!(writer, source) do
    if writer.authority in [:flow_version_rows, :scene_version_rows, :sheet_version_rows] do
      assert source =~ ~s(@entity_type "#{writer.entity_type}")
      assert source =~ "entity_type: @entity_type"
      assert source =~ "version.entity_type == @entity_type"

      for mapping_path <- writer.mapping_paths do
        assert File.read!(mapping_path) =~
                 ~s|validate_inclusion(:entity_type, ["#{writer.entity_type}"])|
      end
    end
  end

  defp assert_entity_version_delete_scope!(writer, source) do
    for function <- writer.functions, :delete_all in function.operations do
      function_source = source_for_function_identities(source, writer.path, [function.identity])
      assert function_source =~ ~s(entity_type == "#{writer.entity_type}")
    end
  end

  defp shared_write_identity(table, write), do: {table, write.path, write.function, write.operation}

  defp shared_mapping(table, context, role, module, path, owner_eligible? \\ true) do
    %{
      table: table,
      context: context,
      role: role,
      module: module,
      path: path,
      owner_eligible?: owner_eligible?
    }
  end

  defp reference_ownership_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> Map.fetch!(:persistence_ownership)
    |> Map.take(@reference_tables)
  end

  defp owned_inventory_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> Map.fetch!(:persistence_ownership)
    |> Map.take(@owned_inventory_tables)
  end

  defp aggregate_identity_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> Map.fetch!(:persistence_ownership)
    |> Map.take(@aggregate_identity_tables)
  end

  defp ownership_invariant_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> Map.fetch!(:canonical_owner_membership_invariant)
  end

  defp valid_eng108_functions?(functions) do
    functions != [] and
      functions == Enum.sort_by(functions, & &1.identity) and
      Enum.all?(functions, fn function ->
        is_binary(function.identity) and function.identity != "" and
          function.detected_by_analyzer == true and
          function.operations != [] and
          function.operations == function.operations |> Enum.uniq() |> Enum.sort()
      end)
  end

  defp declared_eng108_scanner_writes(contract) do
    detected_writers =
      Enum.flat_map(contract.writers, fn writer ->
        Enum.flat_map(writer.functions, &declared_function_writes(writer.path, &1))
      end)

    false_positives =
      Enum.map(contract.scanner_false_positives, fn candidate ->
        Map.take(candidate, [:path, :function, :operation])
      end)

    sort_write_inventory(detected_writers ++ false_positives)
  end

  defp source_function_identities(source, path) do
    source
    |> quoted!(path)
    |> function_clauses()
    |> Enum.map(& &1.identity)
    |> Enum.uniq()
  end

  defp source_for_function_identities(source, path, identities) do
    source
    |> quoted!(path)
    |> function_clauses()
    |> Enum.filter(&(&1.identity in identities))
    |> Enum.map_join("\n", fn clause ->
      Macro.to_string(clause.head) <> "\n" <> Macro.to_string(clause.body)
    end)
  end

  defp literal_word_list_attribute(source, path, attribute) do
    expression =
      source
      |> quoted!(path)
      |> module_attribute_expressions()
      |> Map.fetch!(attribute)

    case expression do
      {:sigil_w, _meta, [{:<<>>, _binary_meta, [words]}, []]} when is_binary(words) ->
        String.split(words)

      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1),
          do: values,
          else: flunk("@#{attribute} in #{path} must be a literal list of strings")

      _other ->
        flunk("@#{attribute} in #{path} must be a literal ~w() or string list")
    end
  end

  defp sha256(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end

  defp source_function_write_operations(source, path, identity) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)

    ast
    |> function_clauses()
    |> Enum.filter(&(&1.identity == identity))
    |> Enum.flat_map(&function_clause_write_operations(&1, aliases, imports))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp function_clause_write_operations(clause, aliases, imports) do
    {_body, operations} =
      Macro.prewalk(clause.body, [], fn node, operations ->
        {node, collect_persistence_write_operation(node, operations, aliases, imports)}
      end)

    operations
  end

  defp collect_persistence_write_operation(node, operations, aliases, imports) do
    case persistence_write_call(node, aliases, imports) do
      {:ok, _kind, operation, _arguments, _meta} -> [operation | operations]
      :not_a_write -> operations
    end
  end

  defp detected_reference_writes(table, schemas) do
    # Association joins may expose the target only through reflected Ecto
    # metadata, so `assoc(` must be a candidate even when the table or target
    # schema name is absent from the source.
    markers =
      [table | schemas] ++
        Enum.map(schemas, fn schema -> schema |> String.split(".") |> List.last() end)

    @storyarn_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      source = File.read!(path)

      if String.contains?(source, markers) or String.contains?(source, "assoc(") do
        table_mutations(source, path, schemas, table)
      else
        []
      end
    end)
    |> Enum.map(&Map.delete(&1, :line))
    |> Enum.uniq()
    |> sort_write_inventory()
  end

  defp declared_reference_writes(contract) do
    (contract.ordinary_writers ++ contract.privileged_writers)
    |> Enum.flat_map(&declared_writer_writes/1)
    |> sort_write_inventory()
  end

  defp declared_writer_writes(writer) do
    Enum.flat_map(writer.functions, &declared_function_writes(writer.path, &1))
  end

  defp declared_function_writes(path, function) do
    Enum.map(function.operations, fn operation ->
      %{path: path, function: function.identity, operation: operation}
    end)
  end

  defp sort_write_inventory(inventory) do
    Enum.sort_by(inventory, &{&1.path, &1.function, &1.operation})
  end

  defp valid_declared_functions?(functions) do
    functions == Enum.sort_by(functions, & &1.identity) and
      Enum.all?(functions, fn function ->
        is_binary(function.identity) and function.identity != "" and
          function.operations != [] and
          function.operations == function.operations |> Enum.uniq() |> Enum.sort()
      end)
  end

  @doc false
  def schema_modules(root, table) do
    root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> quoted!(path)
      |> schema_modules_for(table)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp schema_modules_for(ast, table) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _, segments}, [do: body]]} = node, modules ->
          if defines_schema?(body, table) do
            {node, [module_name(segments) | modules]}
          else
            {node, modules}
          end

        node, modules ->
          {node, modules}
      end)

    modules
  end

  defp defines_schema?(ast, table) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:schema, _meta, [^table | _rest]} = node, _found? -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  @doc false
  def table_mutations(source, path, schemas, table) do
    {violations, unresolved} = table_mutation_analysis(source, path, schemas, table)

    case unresolved do
      [] ->
        violations

      [%{line: line, function: function} | _rest] ->
        raise ArgumentError,
              "cannot resolve raw SQL in #{path}:#{line} (#{function}) while auditing #{table}"
    end
  end

  defp table_mutation_analysis(source, path, schemas, table) do
    ast = quoted!(source, path)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    clauses = function_clauses(ast)
    attributes = binary_module_attributes(ast)

    repo_parameters =
      fixed_point(MapSet.new(), fn parameters ->
        propagate_repo_parameters(clauses, aliases, parameters)
      end)

    analysis =
      fixed_point(%{parameters: MapSet.new(), returns: MapSet.new()}, fn analysis ->
        propagate_module_taint(clauses, schemas, aliases, analysis, table)
      end)

    base_context = %{
      aliases: aliases,
      analysis: analysis,
      attributes: attributes,
      clauses: clauses,
      imports: imports,
      repo_parameters: repo_parameters,
      schemas: schemas,
      table: table
    }

    {violations, unresolved} =
      Enum.reduce(clauses, {[], []}, fn clause, {violations, unresolved} ->
        tainted = clause_tainted_variables(clause, schemas, aliases, analysis, clauses, table)
        repo_variables = clause_repo_variables(clause, aliases, repo_parameters)
        sql_bindings = resolved_sql_variables(clause.body, attributes, variable_names(clause.params))

        context =
          Map.merge(base_context, %{
            analysis: Map.put(analysis, :repo_variables, repo_variables),
            repo_variables: repo_variables,
            sql_bindings: sql_bindings,
            tainted: tainted
          })

        {clause_violations, clause_unresolved} =
          mutation_analysis(clause.body, path, clause.identity, context)

        {clause_violations ++ violations, clause_unresolved ++ unresolved}
      end)

    {
      violations
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.path, &1.line, &1.function, &1.operation}),
      unresolved
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.path, &1.line, &1.function})
    }
  end

  defp mutation_analysis(ast, path, function, context) do
    {_ast, {violations, unresolved}} =
      Macro.prewalk(ast, {[], []}, fn node, {violations, unresolved} ->
        case table_write(node, context) do
          {:ok, operation, line} ->
            violation = %{path: path, line: line, function: function, operation: operation}
            {node, {[violation | violations], unresolved}}

          {:analysis_error, :unresolved_raw_sql, line} ->
            candidate = %{path: path, line: line, function: function}
            {node, {violations, [candidate | unresolved]}}

          :no_write ->
            {node, {violations, unresolved}}
        end
      end)

    {violations, unresolved}
  end

  defp table_write({:|>, pipe_meta, [_left, _call]} = node, context) do
    normalized_call = normalize_pipeline_calls(node)

    with :not_raw_sql <-
           raw_sql_write(
             node,
             context.aliases,
             context.imports,
             context.attributes,
             context.sql_bindings,
             context.table
           ),
         :not_a_callback <-
           callback_persistence_write(node, context),
         :not_a_write <-
           persistence_write_call(
             normalized_call,
             context.aliases,
             context.imports,
             context.repo_variables
           ) do
      :no_write
    else
      {:ok, operation, meta} when is_list(meta) ->
        {:ok, operation, Keyword.get(meta, :line, Keyword.get(pipe_meta, :line, 0))}

      {:analysis_error, :unresolved_raw_sql, meta} ->
        {:analysis_error, :unresolved_raw_sql, Keyword.get(meta, :line, Keyword.get(pipe_meta, :line, 0))}

      {:ok, kind, operation, arguments, call_meta} ->
        target = persistence_target(kind, arguments)

        if persistence_targets_table?(
             target,
             context.schemas,
             context.aliases,
             context.tainted,
             context.table,
             context.analysis,
             context.clauses,
             context.attributes
           ) do
          {:ok, operation, Keyword.get(call_meta, :line, Keyword.get(pipe_meta, :line, 0))}
        else
          :no_write
        end
    end
  end

  defp table_write(node, context) do
    with :not_raw_sql <-
           raw_sql_write(
             node,
             context.aliases,
             context.imports,
             context.attributes,
             context.sql_bindings,
             context.table
           ),
         :not_a_callback <-
           callback_persistence_write(node, context),
         :not_a_write <-
           persistence_write_call(
             node,
             context.aliases,
             context.imports,
             context.repo_variables
           ) do
      :no_write
    else
      {:ok, operation, meta} when is_list(meta) ->
        {:ok, operation, Keyword.get(meta, :line, 0)}

      {:analysis_error, :unresolved_raw_sql, meta} ->
        {:analysis_error, :unresolved_raw_sql, Keyword.get(meta, :line, 0)}

      {:ok, kind, operation, arguments, meta} ->
        target = persistence_target(kind, arguments)

        if persistence_targets_table?(
             target,
             context.schemas,
             context.aliases,
             context.tainted,
             context.table,
             context.analysis,
             context.clauses,
             context.attributes
           ) do
          {:ok, operation, Keyword.get(meta, :line, 0)}
        else
          :no_write
        end
    end
  end

  defp callback_persistence_write(node, context) do
    with {:ok, arguments, %{callback: callback_index, sources: source_indexes}} <-
           enumerable_callback(node, context.aliases, context.imports),
         true <-
           Enum.any?(source_indexes, fn index ->
             arguments
             |> Enum.at(index)
             |> targets_table?(
               context.schemas,
               context.aliases,
               context.tainted,
               context.table,
               context.analysis,
               context.clauses
             )
           end),
         callback when not is_nil(callback) <- Enum.at(arguments, callback_index),
         {:ok, operation, meta} <-
           captured_persistence_write(
             callback,
             context.aliases,
             context.imports,
             context.repo_variables
           ) do
      {:ok, operation, meta}
    else
      _other -> :not_a_callback
    end
  end

  defp captured_persistence_write(
         {:&, meta, [{:/, _, [{{:., _, [{:__aliases__, _, segments}, operation]}, _, []}, 1]}]},
         aliases,
         _imports,
         _repo_variables
       )
       when operation in @repo_write_functions do
    if repo_module?(expanded_modules(segments, aliases)),
      do: {:ok, operation, meta},
      else: :not_a_persistence_capture
  end

  defp captured_persistence_write(
         {:&, meta, [{:/, _, [{{:., _, [{name, _, context}, operation]}, _, []}, 1]}]},
         _aliases,
         _imports,
         repo_variables
       )
       when is_atom(name) and is_atom(context) and operation in @repo_write_functions do
    if MapSet.member?(repo_variables, name),
      do: {:ok, operation, meta},
      else: :not_a_persistence_capture
  end

  defp captured_persistence_write({:&, meta, [call]}, aliases, imports, repo_variables) do
    case persistence_write_call(call, aliases, imports, repo_variables) do
      {:ok, _kind, operation, arguments, _call_meta} ->
        if Enum.any?(arguments, &match?({:&, _, [position]} when is_integer(position), &1)),
          do: {:ok, operation, meta},
          else: :not_a_persistence_capture

      :not_a_write ->
        :not_a_persistence_capture
    end
  end

  defp captured_persistence_write({:fn, _, callback_clauses}, aliases, imports, repo_variables) do
    Enum.find_value(
      callback_clauses,
      :not_a_persistence_capture,
      &anonymous_callback_persistence_write(&1, aliases, imports, repo_variables)
    )
  end

  defp captured_persistence_write(_callback, _aliases, _imports, _repo_variables), do: :not_a_persistence_capture

  defp anonymous_callback_persistence_write({:->, _, [patterns, body]}, aliases, imports, repo_variables) do
    body = normalize_pipeline_calls(body)

    context = %{
      aliases: aliases,
      callback_variables: callback_derived_variables(body, variable_names(patterns), aliases),
      imports: imports,
      repo_variables: repo_variables
    }

    {_body, write} = Macro.prewalk(body, nil, &collect_anonymous_callback_write(&1, &2, context))

    write
  end

  defp anonymous_callback_persistence_write(_callback_clause, _aliases, _imports, _repo_variables), do: nil

  defp callback_derived_variables(body, initial, aliases) do
    fixed_point(initial, fn current ->
      {_body, derived} =
        Macro.prewalk(body, current, fn node, found ->
          found = propagate_callback_assignment(node, found)
          {node, propagate_nested_callback_parameters(node, found, aliases)}
        end)

      derived
    end)
  end

  defp propagate_callback_assignment({operator, _, [left, right]}, current) when operator in [:=, :<-] do
    if variables_derived_from?(right, current),
      do: MapSet.union(current, variable_names(left)),
      else: current
  end

  defp propagate_callback_assignment(_node, current), do: current

  defp propagate_nested_callback_parameters(node, current, aliases) do
    with {:ok, module, _function, arguments} <- remote_call(node, aliases),
         true <- module in ["Enum", "Stream", "Task", "Task.Supervisor"],
         callbacks when callbacks != [] <- Enum.filter(arguments, &match?({:fn, _, _}, &1)),
         sources = arguments -- callbacks,
         true <- Enum.any?(sources, &variables_derived_from?(&1, current)) do
      callbacks
      |> Enum.flat_map(&anonymous_callback_pattern_variables/1)
      |> MapSet.new()
      |> MapSet.union(current)
    else
      _other -> current
    end
  end

  defp anonymous_callback_pattern_variables({:fn, _, clauses}) do
    Enum.flat_map(clauses, fn
      {:->, _, [patterns, _body]} -> variable_names(patterns)
      _other -> []
    end)
  end

  defp variables_derived_from?(ast, current) do
    ast
    |> variable_names()
    |> MapSet.disjoint?(current)
    |> Kernel.not()
  end

  defp collect_anonymous_callback_write(node, nil, context) do
    case persistence_write_call(node, context.aliases, context.imports, context.repo_variables) do
      {:ok, kind, operation, arguments, meta} ->
        target_variables = kind |> persistence_target(arguments) |> variable_names()

        if MapSet.disjoint?(context.callback_variables, target_variables),
          do: {node, nil},
          else: {node, {:ok, operation, meta}}

      :not_a_write ->
        {node, nil}
    end
  end

  defp collect_anonymous_callback_write(node, write, _context), do: {node, write}

  defp raw_sql_write(node, aliases, imports, attributes, sql_bindings, table) do
    case raw_sql_call(node, aliases, imports) do
      {:ok, sql_ast, meta} ->
        resolved_raw_sql_write(sql_ast, meta, attributes, sql_bindings, table)

      :not_raw_sql ->
        :not_raw_sql
    end
  end

  # A pipeline inserts its left side as the first argument. Normalize it before
  # selecting the SQL argument because Repo expects SQL first while
  # Ecto.Adapters.SQL expects the Repo followed by SQL.
  defp resolved_raw_sql_write(sql_ast, _meta, _attributes, _sql_bindings, _table) when is_list(sql_ast), do: :not_raw_sql

  defp resolved_raw_sql_write(sql_ast, meta, attributes, sql_bindings, table) do
    case resolve_sql(sql_ast, attributes, sql_bindings) do
      {:ok, sql} -> raw_sql_operation(sql, table, meta)
      :error -> {:analysis_error, :unresolved_raw_sql, meta}
    end
  end

  defp raw_sql_operation(sql, table, meta) do
    case sql_mutation_operation(sql, table) do
      nil -> :not_raw_sql
      operation -> {:ok, operation, meta}
    end
  end

  defp raw_sql_call({:|>, pipe_meta, [left, {{:., dot_meta, receiver}, call_meta, arguments}]}, aliases, imports)
       when is_list(arguments) do
    raw_sql_call(
      {{:., dot_meta, receiver}, Keyword.merge(pipe_meta, call_meta), [left | arguments]},
      aliases,
      imports
    )
  end

  defp raw_sql_call({:|>, pipe_meta, [left, {operation, call_meta, arguments}]}, aliases, imports)
       when is_atom(operation) and is_list(arguments) do
    raw_sql_call({operation, Keyword.merge(pipe_meta, call_meta), [left | arguments]}, aliases, imports)
  end

  defp raw_sql_call({{:., _, [{name, _, context}, operation]}, meta, [sql_ast | _arguments]}, _aliases, _imports)
       when is_atom(name) and is_atom(context) and operation in @repo_raw_sql_functions do
    {:ok, sql_ast, meta}
  end

  defp raw_sql_call({{:., _, [{:__aliases__, _, segments}, operation]}, meta, arguments}, aliases, _imports)
       when operation in @repo_raw_sql_functions do
    modules = expanded_modules(segments, aliases)

    cond do
      ecto_adapters_sql_module?(modules) -> raw_sql_argument(arguments, 1, meta)
      repo_module?(modules) -> raw_sql_argument(arguments, 0, meta)
      true -> :not_raw_sql
    end
  end

  defp raw_sql_call({operation, meta, arguments}, _aliases, imports)
       when operation in @repo_raw_sql_functions and is_list(arguments) do
    arity = length(arguments)

    cond do
      imported_function?(imports, "Ecto.Adapters.SQL", operation, arity) ->
        raw_sql_argument(arguments, 1, meta)

      imported_function?(imports, "Storyarn.Repo", operation, arity) ->
        raw_sql_argument(arguments, 0, meta)

      true ->
        :not_raw_sql
    end
  end

  defp raw_sql_call(_node, _aliases, _imports), do: :not_raw_sql

  defp raw_sql_argument(arguments, index, meta) do
    case Enum.fetch(arguments, index) do
      {:ok, sql} -> {:ok, sql, meta}
      :error -> :not_raw_sql
    end
  end

  defp binary_module_attributes(ast) do
    expressions = module_attribute_expressions(ast)
    fixed_point(%{}, &resolve_attribute_expressions(expressions, &1))
  end

  defp literal_binary_module_attributes(ast) do
    ast
    |> module_attribute_expressions()
    |> Enum.reduce(%{}, fn
      {name, value}, attributes when is_binary(value) -> Map.put(attributes, name, value)
      {_name, _value}, attributes -> attributes
    end)
  end

  defp module_attribute_expressions(ast) do
    {_ast, expressions} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, attributes when is_atom(name) ->
          {node, Map.put(attributes, name, value)}

        node, attributes ->
          {node, attributes}
      end)

    expressions
  end

  defp resolve_attribute_expressions(expressions, attributes) do
    Enum.reduce(expressions, attributes, fn {name, expression}, resolved ->
      put_resolved_sql(resolved, name, resolve_sql(expression, resolved, %{}))
    end)
  end

  defp resolved_sql_variables(ast, attributes, initially_bound_variables) do
    bindings = fixed_point(%{}, &resolve_sql_variables_pass(ast, attributes, &1))

    ast
    |> assignment_counts(initially_bound_variables)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
    |> then(&Map.drop(bindings, &1))
  end

  defp assignment_counts(ast, initially_bound_variables) do
    initial_counts = Map.new(initially_bound_variables, &{&1, 1})

    {_ast, counts} =
      Macro.prewalk(ast, initial_counts, fn
        {operator, _, [{name, _, context}, _expression]} = node, current
        when operator in [:=, :<-] and is_atom(name) and is_atom(context) ->
          {node, Map.update(current, name, 1, &(&1 + 1))}

        node, current ->
          {node, current}
      end)

    counts
  end

  defp resolve_sql_variables_pass(ast, attributes, bindings) do
    {_ast, next} =
      Macro.prewalk(ast, bindings, fn
        {:=, _, [{name, _, context}, expression]} = node, current
        when is_atom(name) and is_atom(context) ->
          resolved = resolve_sql(expression, attributes, current)
          {node, put_resolved_sql(current, name, resolved)}

        node, current ->
          {node, current}
      end)

    next
  end

  defp put_resolved_sql(current, name, {:ok, value}), do: Map.put(current, name, value)
  defp put_resolved_sql(current, name, :error), do: Map.delete(current, name)

  defp resolve_sql(sql, _attributes, _bindings) when is_binary(sql), do: {:ok, sql}

  defp resolve_sql({:@, _, [{name, _, _context}]}, attributes, _bindings) when is_atom(name) do
    Map.fetch(attributes, name)
  end

  defp resolve_sql({name, _, context}, _attributes, bindings) when is_atom(name) and is_atom(context) do
    Map.fetch(bindings, name)
  end

  defp resolve_sql({:<>, _, [left, right]}, attributes, bindings) do
    with {:ok, left} <- resolve_sql(left, attributes, bindings),
         {:ok, right} <- resolve_sql(right, attributes, bindings) do
      {:ok, left <> right}
    end
  end

  defp resolve_sql(_sql, _attributes, _bindings), do: :error

  defp sql_mutation_operation(sql, table) do
    sql =
      sql
      |> String.replace(~r|/\*.*?\*/|s, " ")
      |> String.replace(~r/--[^\n]*/, " ")

    identifier =
      "(?:\"?[A-Za-z_][A-Za-z0-9_$]*\"?\\.)?\"?#{Regex.escape(table)}\"?(?![A-Za-z0-9_$])"

    Enum.find_value(
      [
        {:insert, ~r/\binsert\s+into\s+#{identifier}/i},
        {:delete, ~r/\bdelete\s+from\s+(?:only\s+)?#{identifier}/i},
        {:update, ~r/\bupdate\s+(?:only\s+)?#{identifier}/i},
        {:insert, ~r/\bmerge\s+into\s+#{identifier}/i},
        {:delete_all, ~r/\btruncate\s+(?:table\s+)?#{identifier}/i}
      ],
      fn {operation, pattern} -> if Regex.match?(pattern, sql), do: operation end
    )
  end

  defp persistence_write_call(node, aliases, imports, repo_variables \\ MapSet.new())

  defp persistence_write_call(
         {{:., _, [{:__aliases__, _, segments}, operation]}, meta, arguments},
         aliases,
         _imports,
         repo_variables
       )
       when is_atom(operation) and is_list(arguments) do
    modules = expanded_modules(segments, aliases)

    cond do
      repo_module?(modules) and operation in @repo_write_functions ->
        {:ok, :repo, operation, arguments, meta}

      multi_module?(modules) and operation in @multi_write_functions ->
        {:ok, :multi, operation, arguments, meta}

      delegate = transparent_write_delegate(modules, operation, length(arguments)) ->
        if repo_ast?(Enum.at(arguments, delegate.repo_argument), aliases, repo_variables) do
          {:ok, {:schema_helper, delegate.schema_argument}, delegate.operation, arguments, meta}
        else
          :not_a_write
        end

      true ->
        :not_a_write
    end
  end

  defp persistence_write_call(
         {{:., _, [{name, _, context}, operation]}, meta, arguments},
         _aliases,
         _imports,
         repo_variables
       )
       when is_atom(name) and is_atom(context) and operation in @repo_write_functions and is_list(arguments) do
    if MapSet.member?(repo_variables, name),
      do: {:ok, :repo, operation, arguments, meta},
      else: :not_a_write
  end

  defp persistence_write_call({operation, meta, arguments}, _aliases, imports, _repo_variables)
       when is_atom(operation) and operation != :apply and is_list(arguments) do
    arity = length(arguments)

    cond do
      operation in @repo_write_functions and
          imported_function?(imports, "Storyarn.Repo", operation, arity) ->
        {:ok, :repo, operation, arguments, meta}

      operation in @multi_write_functions and
          imported_function?(imports, "Ecto.Multi", operation, arity) ->
        {:ok, :multi, operation, arguments, meta}

      true ->
        :not_a_write
    end
  end

  defp persistence_write_call({:apply, meta, [module, operation, arguments]}, aliases, _imports, repo_variables)
       when operation in @repo_write_functions and is_list(arguments) do
    if repo_ast?(module, aliases, repo_variables),
      do: {:ok, :repo, operation, arguments, meta},
      else: :not_a_write
  end

  defp persistence_write_call(
         {{:., _, [{:__aliases__, _, kernel_segments}, :apply]}, meta, [module, operation, arguments]},
         aliases,
         _imports,
         repo_variables
       )
       when operation in @repo_write_functions and is_list(arguments) do
    if Enum.any?(expanded_modules(kernel_segments, aliases), &(module_name(&1) == "Kernel")) and
         repo_ast?(module, aliases, repo_variables) do
      {:ok, :repo, operation, arguments, meta}
    else
      :not_a_write
    end
  end

  defp persistence_write_call(_node, _aliases, _imports, _repo_variables), do: :not_a_write

  defp persistence_target(:repo, arguments), do: Enum.at(arguments, 0)
  defp persistence_target(:multi, arguments), do: Enum.at(arguments, 2)
  defp persistence_target({:schema_helper, schema_argument}, arguments), do: Enum.at(arguments, schema_argument)

  defp function_clauses(ast) do
    {_ast, {clauses, _next_id}} =
      Macro.prewalk(ast, {[], 0}, fn
        {visibility, meta, [head, body_options]} = node, {clauses, next_id}
        when visibility in [:def, :defp] and is_list(body_options) ->
          case {function_head(head), Keyword.fetch(body_options, :do)} do
            {{name, arguments}, {:ok, body}} ->
              arity = length(arguments)
              default_count = Enum.count(arguments, &match?({:\\, _, [_argument, _default]}, &1))

              clause = %{
                id: next_id,
                visibility: visibility,
                name: name,
                arity: arity,
                accepted_arities: MapSet.new((arity - default_count)..arity),
                params: Enum.map(arguments, &strip_default_argument/1),
                head: head,
                body: body,
                identity: function_identity(visibility, head),
                line: Keyword.get(meta, :line, 0)
              }

              {node, {[clause | clauses], next_id + 1}}

            _other ->
              {node, {clauses, next_id}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(clauses)
  end

  defp function_head({:when, _, [head | _guards]}), do: function_head(head)
  defp function_head({name, _, arguments}) when is_atom(name), do: {name, arguments || []}
  defp function_head(_head), do: :unknown

  defp strip_default_argument({:\\, _, [argument, _default]}), do: argument
  defp strip_default_argument(argument), do: argument

  defp propagate_module_taint(clauses, schemas, aliases, analysis, table) do
    Enum.reduce(clauses, analysis, fn clause, next_analysis ->
      tainted = clause_tainted_variables(clause, schemas, aliases, analysis, clauses, table)

      next_analysis =
        propagate_local_call_parameters(
          clause.body,
          clauses,
          schemas,
          aliases,
          tainted,
          table,
          analysis,
          next_analysis
        )

      if clause_returns_target?(clause.body, schemas, aliases, tainted, table, analysis, clauses) do
        %{next_analysis | returns: MapSet.put(next_analysis.returns, clause.id)}
      else
        next_analysis
      end
    end)
  end

  defp clause_tainted_variables(clause, schemas, aliases, analysis, clauses, table) do
    parameter_taint =
      clause.params
      |> Enum.with_index()
      |> Enum.reduce(MapSet.new(), fn {parameter, index}, tainted ->
        if MapSet.member?(analysis.parameters, {clause.id, index}),
          do: MapSet.union(tainted, variable_names(parameter)),
          else: tainted
      end)

    ast = {:__block__, [], [clause.head, clause.body]}

    fixed_point(parameter_taint, fn tainted ->
      {_ast, next} =
        Macro.prewalk(ast, tainted, fn node, current ->
          current = taint_assignment(node, current, schemas, aliases, table, analysis, clauses)
          current = taint_case_patterns(node, current, schemas, aliases, table, analysis, clauses)
          {node, taint_callback_parameters(node, current, schemas, aliases, table, analysis, clauses)}
        end)

      next
    end)
  end

  defp taint_assignment({operator, _meta, [left, right]}, current, schemas, aliases, table, analysis, clauses)
       when operator in [:=, :<-] do
    cond do
      targets_table?(right, schemas, aliases, current, table, analysis, clauses) ->
        MapSet.union(current, variable_names(left))

      assignment_pattern_targets_table?(left, schemas, aliases) ->
        current
        |> MapSet.union(variable_names(left))
        |> MapSet.union(variable_names(right))

      true ->
        current
    end
  end

  defp taint_assignment(_node, current, _schemas, _aliases, _table, _analysis, _clauses), do: current

  # Assignment data flows from the expression on the right into the binding on
  # the left. Propagating every variable name in both directions makes an
  # unrelated record used inside a query look like that query's result. A
  # schema pattern is the one deliberate reverse-flow case: `%Schema{} = row`
  # proves that `row` is a value of the mapped table.
  defp assignment_pattern_targets_table?(left, schemas, aliases) do
    {_left, target?} =
      Macro.prewalk(left, false, fn
        {:%, _, [{:__aliases__, _, segments}, _fields]} = node, target? ->
          {node, target? or module_targets_table?(segments, schemas, aliases)}

        node, target? ->
          {node, target?}
      end)

    target?
  end

  defp taint_case_patterns({:case, _, [scrutinee, [do: branches]]}, current, schemas, aliases, table, analysis, clauses)
       when is_list(branches) do
    if targets_table?(scrutinee, schemas, aliases, current, table, analysis, clauses) do
      Enum.reduce(branches, current, fn
        {:->, _, [patterns, _body]}, tainted -> MapSet.union(tainted, variable_names(patterns))
        _branch, tainted -> tainted
      end)
    else
      current
    end
  end

  defp taint_case_patterns(_node, current, _schemas, _aliases, _table, _analysis, _clauses), do: current

  defp taint_callback_parameters(node, current, schemas, aliases, table, analysis, clauses) do
    case enumerable_callback(node, aliases) do
      {:ok, arguments, %{callback: callback_index, sources: source_indexes}} ->
        callback = Enum.at(arguments, callback_index)

        source_taints =
          Enum.map(source_indexes, fn index ->
            arguments
            |> Enum.at(index)
            |> targets_table?(schemas, aliases, current, table, analysis, clauses)
          end)

        taint_anonymous_callback_parameters(callback, source_taints, current)

      :not_a_callback ->
        current
    end
  end

  defp taint_anonymous_callback_parameters({:fn, _, callback_clauses}, source_taints, current) do
    Enum.reduce(callback_clauses, current, &taint_callback_clause(&1, source_taints, &2))
  end

  defp taint_anonymous_callback_parameters(_capture, _source_taints, current), do: current

  defp taint_callback_clause({:->, _, [parameters, _body]}, source_taints, tainted) do
    parameters
    |> Enum.with_index()
    |> Enum.reduce(tainted, &taint_callback_parameter(&1, source_taints, &2))
  end

  defp taint_callback_clause(_node, _source_taints, tainted), do: tainted

  defp taint_callback_parameter({parameter, index}, source_taints, tainted) do
    if Enum.at(source_taints, index, false),
      do: MapSet.union(tainted, variable_names(parameter)),
      else: tainted
  end

  defp propagate_local_call_parameters(ast, clauses, schemas, aliases, tainted, table, analysis, next_analysis) do
    context = %{
      aliases: aliases,
      analysis: analysis,
      clauses: clauses,
      schemas: schemas,
      table: table,
      tainted: tainted
    }

    {_ast, propagated} =
      Macro.prewalk(ast, next_analysis, fn node, acc ->
        acc =
          case local_call(node) do
            {:ok, name, arguments} ->
              propagate_call_arguments(name, arguments, context, acc)

            :not_a_local_call ->
              acc
          end

        {node, propagate_captured_callback(node, context, acc)}
      end)

    propagated
  end

  defp propagate_call_arguments(name, arguments, context, next_analysis) do
    context.clauses
    |> matching_clauses(name, length(arguments))
    |> Enum.reduce(next_analysis, &propagate_clause_arguments(&1, arguments, context, &2))
  end

  defp propagate_clause_arguments(clause, arguments, context, analysis) do
    arguments
    |> Enum.with_index()
    |> Enum.reduce(analysis, &propagate_clause_argument(&1, clause, context, &2))
  end

  defp propagate_clause_argument({argument, index}, clause, context, analysis) do
    if target_argument?(argument, context),
      do: put_tainted_parameter(analysis, clause, index),
      else: analysis
  end

  defp propagate_captured_callback(node, context, next_analysis) do
    with {:ok, arguments, %{callback: callback_index, sources: source_indexes}} <-
           enumerable_callback(node, context.aliases, Map.get(context, :imports, [])),
         callback when not is_nil(callback) <- Enum.at(arguments, callback_index),
         source_taints =
           Enum.map(source_indexes, fn index ->
             arguments |> Enum.at(index) |> target_argument?(context)
           end),
         {:ok, name, argument_taints} <- captured_local_call(callback, source_taints) do
      propagate_captured_call(name, argument_taints, context, next_analysis)
    else
      _other -> next_analysis
    end
  end

  defp propagate_captured_call(name, argument_taints, context, analysis) do
    context.clauses
    |> matching_clauses(name, length(argument_taints))
    |> Enum.reduce(analysis, &propagate_captured_clause(&1, argument_taints, &2))
  end

  defp propagate_captured_clause(clause, argument_taints, analysis) do
    argument_taints
    |> Enum.with_index()
    |> Enum.reduce(analysis, fn {target?, index}, acc ->
      if target?, do: put_tainted_parameter(acc, clause, index), else: acc
    end)
  end

  defp target_argument?(argument, context) do
    targets_table?(
      argument,
      context.schemas,
      context.aliases,
      context.tainted,
      context.table,
      context.analysis,
      context.clauses
    )
  end

  defp put_tainted_parameter(analysis, clause, index) do
    %{analysis | parameters: MapSet.put(analysis.parameters, {clause.id, index})}
  end

  defp captured_local_call({:&, _, [{:/, _, [{name, _, context}, arity]}]}, source_taints)
       when is_atom(name) and is_atom(context) and is_integer(arity) and arity >= 0 do
    {:ok, name, Enum.map(1..arity//1, &Enum.at(source_taints, &1 - 1, false))}
  end

  defp captured_local_call({:&, _, [{name, _, arguments}]}, source_taints) when is_atom(name) and is_list(arguments) do
    {:ok, name, Enum.map(arguments, &captured_argument_tainted?(&1, source_taints))}
  end

  defp captured_local_call(_callback, _source_taints), do: :not_a_local_capture

  defp captured_argument_tainted?({:&, _, [position]}, source_taints) when is_integer(position) and position > 0,
    do: Enum.at(source_taints, position - 1, false)

  defp captured_argument_tainted?(_argument, _source_taints), do: false

  defp clause_returns_target?(ast, schemas, aliases, tainted, table, analysis, clauses) do
    ast
    |> return_expressions()
    |> Enum.any?(&targets_table?(&1, schemas, aliases, tainted, table, analysis, clauses))
  end

  defp return_expressions({:__block__, _, expressions}), do: return_expressions(List.last(expressions))

  defp return_expressions({form, _, arguments}) when form in [:if, :unless, :with, :case, :cond, :receive, :try] do
    arguments
    |> Enum.filter(&is_list/1)
    |> Enum.flat_map(fn options ->
      options
      |> Keyword.take([:do, :else, :rescue, :catch])
      |> Keyword.values()
      |> Enum.flat_map(&branch_return_expressions/1)
    end)
    |> case do
      [] -> [{form, [], arguments}]
      expressions -> expressions
    end
  end

  defp return_expressions(nil), do: []
  defp return_expressions(ast), do: [ast]

  defp branch_return_expressions(clauses) when is_list(clauses) do
    Enum.flat_map(clauses, fn
      {:->, _, [_patterns, body]} -> return_expressions(body)
      expression -> return_expressions(expression)
    end)
  end

  defp branch_return_expressions(expression), do: return_expressions(expression)

  defp matching_clauses(clauses, name, arity) do
    Enum.filter(clauses, &(&1.name == name and MapSet.member?(&1.accepted_arities, arity)))
  end

  defp local_call({:|>, _, [left, {name, _, arguments}]}) when is_atom(name) and is_list(arguments),
    do: {:ok, name, [left | arguments]}

  defp local_call({name, _, arguments}) when is_atom(name) and is_list(arguments), do: {:ok, name, arguments}

  defp local_call(_node), do: :not_a_local_call

  defp enumerable_callback(node, aliases, imports \\ [])

  defp enumerable_callback({:|>, _, [left, call]}, aliases, imports) do
    case remote_call(call, aliases) do
      {:ok, module, function, arguments} ->
        enumerable_callback_for_module(module, function, [left | arguments])

      :not_a_remote_call ->
        imported_enumerable_callback(call, imports, [left])
    end
  end

  defp enumerable_callback(node, aliases, imports) do
    case remote_call(node, aliases) do
      {:ok, module, function, arguments} -> enumerable_callback_for_module(module, function, arguments)
      :not_a_remote_call -> imported_enumerable_callback(node, imports, [])
    end
  end

  defp enumerable_callback_for_module(module, function, arguments) when module in ["Enum", "Stream"] do
    callback_spec(@enumerable_callback_functions, function, arguments)
  end

  defp enumerable_callback_for_module("Task", function, arguments),
    do: callback_spec(@task_callback_functions, function, arguments)

  defp enumerable_callback_for_module(_module, _function, _arguments), do: :not_a_callback

  defp callback_spec(specs, function, arguments) do
    case Map.get(specs, function) do
      %{arities: arities} = spec ->
        if length(arguments) in arities, do: {:ok, arguments, spec}, else: :not_a_callback

      %{callback: callback_index} = spec when length(arguments) == callback_index + 1 ->
        {:ok, arguments, spec}

      _other ->
        :not_a_callback
    end
  end

  defp imported_enumerable_callback({function, _, arguments}, imports, piped_arguments)
       when is_atom(function) and is_list(arguments) do
    arguments = piped_arguments ++ arguments

    ["Enum", "Stream", "Task"]
    |> Enum.filter(&imported_function?(imports, &1, function, length(arguments)))
    |> Enum.find_value(:not_a_callback, &enumerable_callback_for_module(&1, function, arguments))
  end

  defp imported_enumerable_callback(_node, _imports, _piped_arguments), do: :not_a_callback

  defp remote_call({{:., _, [{:__aliases__, _, segments}, function]}, _, arguments}, aliases)
       when is_atom(function) and is_list(arguments) do
    module = segments |> expanded_modules(aliases) |> Enum.map(&module_name/1) |> List.last()
    {:ok, module, function, arguments}
  end

  defp remote_call(_node, _aliases), do: :not_a_remote_call

  defp fixed_point(current, step) do
    case step.(current) do
      ^current -> current
      next -> fixed_point(next, step)
    end
  end

  defp propagate_repo_parameters(clauses, aliases, repo_parameters) do
    votes =
      Enum.reduce(clauses, %{}, fn clause, votes ->
        repo_variables = clause_repo_variables(clause, aliases, repo_parameters)

        body = normalize_pipeline_calls(clause.body)
        body_without_multi_callbacks = strip_multi_run_callback_bodies(body, aliases)

        {_body, votes} =
          Macro.prewalk(body_without_multi_callbacks, votes, fn node, current_votes ->
            current_votes = record_local_repo_call_votes(node, clauses, aliases, repo_variables, current_votes)
            {node, current_votes}
          end)

        record_multi_run_callback_votes(
          body,
          clauses,
          aliases,
          repo_variables,
          votes
        )
      end)

    proven =
      votes
      |> Enum.filter(fn {_parameter, callsite_votes} ->
        callsite_votes != [] and Enum.all?(callsite_votes)
      end)
      |> MapSet.new(&elem(&1, 0))

    MapSet.union(repo_parameters, proven)
  end

  defp record_multi_run_callback_votes(body, clauses, aliases, repo_variables, votes) do
    body
    |> direct_multi_run_callbacks(aliases)
    |> Enum.reduce(votes, fn callback, current_votes ->
      record_multi_run_callback_call_votes(
        callback,
        clauses,
        aliases,
        repo_variables,
        current_votes
      )
    end)
  end

  defp record_multi_run_callback_call_votes({:fn, _, callback_clauses}, clauses, aliases, outer_repo_variables, votes) do
    Enum.reduce(callback_clauses, votes, fn
      {:->, _, [[first_parameter | _rest], callback_body]}, current_votes ->
        callback_repo_variables =
          outer_repo_variables
          |> MapSet.union(MapSet.new(variable_names(first_parameter)))
          |> MapSet.difference(rebound_variable_names(callback_body))

        body = normalize_pipeline_calls(callback_body)
        body_without_nested_callbacks = strip_multi_run_callback_bodies(body, aliases)

        {_body, current_votes} =
          Macro.prewalk(body_without_nested_callbacks, current_votes, fn node, nested_votes ->
            nested_votes =
              record_local_repo_call_votes(
                node,
                clauses,
                aliases,
                callback_repo_variables,
                nested_votes
              )

            {node, nested_votes}
          end)

        record_multi_run_callback_votes(
          body,
          clauses,
          aliases,
          callback_repo_variables,
          current_votes
        )

      _callback_clause, current_votes ->
        current_votes
    end)
  end

  defp record_multi_run_callback_call_votes(_callback, _clauses, _aliases, _repo_variables, votes), do: votes

  defp record_local_repo_call_votes(node, clauses, aliases, repo_variables, votes) do
    votes = record_local_repo_capture_votes(node, clauses, votes)

    case local_call(node) do
      {:ok, name, arguments} ->
        clauses
        |> matching_clauses(name, length(arguments))
        |> Enum.reduce(votes, fn target_clause, current_votes ->
          record_repo_argument_votes(
            arguments,
            target_clause,
            aliases,
            repo_variables,
            current_votes
          )
        end)

      :not_a_local_call ->
        votes
    end
  end

  defp record_local_repo_capture_votes({:&, _, [{:/, _, [{name, _, context}, arity]}]}, clauses, votes)
       when is_atom(name) and is_atom(context) and is_integer(arity) and arity >= 0 do
    clauses
    |> matching_clauses(name, arity)
    |> Enum.reduce(votes, fn target_clause, current_votes ->
      target_clause.params
      |> Enum.with_index()
      |> Enum.reduce(current_votes, fn {_parameter, index}, acc ->
        Map.update(acc, {target_clause.id, index}, [false], &[false | &1])
      end)
    end)
  end

  defp record_local_repo_capture_votes(_node, _clauses, votes), do: votes

  defp record_repo_argument_votes(arguments, target_clause, aliases, repo_variables, votes) do
    arguments
    |> Enum.with_index()
    |> Enum.reduce(votes, fn {argument, index}, current_votes ->
      Map.update(
        current_votes,
        {target_clause.id, index},
        [repo_value?(argument, aliases, repo_variables)],
        &[repo_value?(argument, aliases, repo_variables) | &1]
      )
    end)
  end

  defp clause_repo_variables(clause, _aliases, repo_parameters) do
    variables =
      clause.params
      |> Enum.with_index()
      |> Enum.reduce(MapSet.new(), fn {parameter, index}, current_variables ->
        if MapSet.member?(repo_parameters, {clause.id, index}),
          do: MapSet.union(current_variables, MapSet.new(variable_names(parameter))),
          else: current_variables
      end)

    MapSet.difference(variables, rebound_variable_names(clause.body))
  end

  defp rebound_variable_names(ast) do
    {_ast, rebound} =
      Macro.prewalk(ast, MapSet.new(), fn
        {operator, _, [left, _right]} = node, current when operator in [:=, :<-] ->
          {node, MapSet.union(current, MapSet.new(variable_names(left)))}

        {:->, _, [patterns, _body]} = node, current ->
          {node, MapSet.union(current, MapSet.new(variable_names(patterns)))}

        node, current ->
          {node, current}
      end)

    rebound
  end

  defp direct_multi_run_callbacks(ast, aliases) do
    {_ast, callbacks} =
      Macro.prewalk(ast, [], fn
        {{:., dot_meta, [{:__aliases__, alias_meta, segments}, :run]}, call_meta, arguments}, callbacks
        when is_list(arguments) ->
          if Enum.any?(expanded_modules(segments, aliases), &(module_name(&1) == "Ecto.Multi")) do
            callback = List.last(arguments)
            stripped_arguments = List.replace_at(arguments, -1, :__ratchet_callback__)

            stripped =
              {{:., dot_meta, [{:__aliases__, alias_meta, segments}, :run]}, call_meta, stripped_arguments}

            {stripped, [callback | callbacks]}
          else
            {{{:., dot_meta, [{:__aliases__, alias_meta, segments}, :run]}, call_meta, arguments}, callbacks}
          end

        node, callbacks ->
          {node, callbacks}
      end)

    Enum.reverse(callbacks)
  end

  defp strip_multi_run_callback_bodies(ast, aliases) do
    {stripped, _callbacks} =
      Macro.prewalk(ast, [], fn
        {{:., dot_meta, [{:__aliases__, alias_meta, segments}, :run]}, call_meta, arguments}, callbacks
        when is_list(arguments) ->
          if Enum.any?(expanded_modules(segments, aliases), &(module_name(&1) == "Ecto.Multi")) do
            callback = List.last(arguments)
            stripped_arguments = List.replace_at(arguments, -1, :__ratchet_callback__)

            stripped =
              {{:., dot_meta, [{:__aliases__, alias_meta, segments}, :run]}, call_meta, stripped_arguments}

            {stripped, [callback | callbacks]}
          else
            {{{:., dot_meta, [{:__aliases__, alias_meta, segments}, :run]}, call_meta, arguments}, callbacks}
          end

        node, callbacks ->
          {node, callbacks}
      end)

    stripped
  end

  defp normalize_pipeline_calls(ast) do
    Macro.postwalk(ast, fn
      {:|>, pipe_meta, [left, {{:., dot_meta, receiver}, call_meta, arguments}]}
      when is_list(arguments) ->
        {{:., dot_meta, receiver}, Keyword.merge(pipe_meta, call_meta), [left | arguments]}

      {:|>, pipe_meta, [left, {function, call_meta, arguments}]}
      when is_atom(function) and is_list(arguments) ->
        {function, Keyword.merge(pipe_meta, call_meta), [left | arguments]}

      node ->
        node
    end)
  end

  defp repo_value?({:__aliases__, _, segments}, aliases, _repo_variables),
    do: repo_module?(expanded_modules(segments, aliases))

  defp repo_value?({name, _, context}, _aliases, repo_variables) when is_atom(name) and is_atom(context),
    do: MapSet.member?(repo_variables, name)

  defp repo_value?({:__block__, _, expressions}, aliases, repo_variables),
    do: expressions |> List.last() |> repo_value?(aliases, repo_variables)

  defp repo_value?(_value, _aliases, _repo_variables), do: false

  defp targets_table?(nil, _schemas, _aliases, _tainted, _table, _analysis, _clauses), do: false

  defp targets_table?({:__aliases__, _, segments}, schemas, aliases, _tainted, _table, _analysis, _clauses) do
    module_targets_table?(segments, schemas, aliases)
  end

  defp targets_table?({name, _, context}, _schemas, _aliases, tainted, _table, _analysis, _clauses)
       when is_atom(name) and is_atom(context) do
    MapSet.member?(tainted, name)
  end

  defp targets_table?({:%, _, [module, _fields]}, schemas, aliases, tainted, table, analysis, clauses) do
    targets_table?(module, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp targets_table?({operator, _, [_left, right]}, schemas, aliases, tainted, table, analysis, clauses)
       when operator in [:=, :<-] do
    targets_table?(right, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp targets_table?({:__block__, _, expressions}, schemas, aliases, tainted, table, analysis, clauses) do
    expressions
    |> List.last()
    |> targets_table?(schemas, aliases, tainted, table, analysis, clauses)
  end

  defp targets_table?({:{}, _, elements}, schemas, aliases, tainted, table, analysis, clauses) do
    Enum.any?(elements, &targets_table?(&1, schemas, aliases, tainted, table, analysis, clauses))
  end

  defp targets_table?({:%{}, _, pairs}, schemas, aliases, tainted, table, analysis, clauses) do
    Enum.any?(pairs, fn
      {_key, value} ->
        targets_table?(value, schemas, aliases, tainted, table, analysis, clauses)

      expression ->
        targets_table?(expression, schemas, aliases, tainted, table, analysis, clauses)
    end)
  end

  defp targets_table?({form, _, _arguments} = ast, schemas, aliases, tainted, table, analysis, clauses)
       when form in [:if, :unless, :with, :case, :cond, :receive, :try] do
    ast
    |> return_expressions()
    |> Enum.any?(&targets_table?(&1, schemas, aliases, tainted, table, analysis, clauses))
  end

  defp targets_table?({operator, _, [left, right]}, schemas, aliases, tainted, table, analysis, clauses)
       when operator in [:||, :or] do
    targets_table?(left, schemas, aliases, tainted, table, analysis, clauses) or
      targets_table?(right, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp targets_table?({:|>, _, [left, call]}, schemas, aliases, tainted, table, analysis, clauses) do
    case call do
      {name, _, arguments} when is_atom(name) and is_list(arguments) ->
        call_returns_target?(
          name,
          [left | arguments],
          clauses,
          schemas,
          aliases,
          tainted,
          table,
          analysis
        )

      {{:., _, [receiver, function]}, _, arguments} when is_atom(function) and is_list(arguments) ->
        remote_call_returns_target?(
          receiver,
          function,
          [left | arguments],
          target_context(clauses, schemas, aliases, tainted, table, analysis)
        )

      _call ->
        false
    end
  end

  defp targets_table?({{:., _, [receiver, function]}, _, arguments}, schemas, aliases, tainted, table, analysis, clauses)
       when is_atom(function) and is_list(arguments) do
    remote_call_returns_target?(
      receiver,
      function,
      arguments,
      target_context(clauses, schemas, aliases, tainted, table, analysis)
    )
  end

  defp targets_table?({name, _, arguments}, schemas, aliases, tainted, table, analysis, clauses)
       when is_atom(name) and is_list(arguments) do
    call_returns_target?(name, arguments, clauses, schemas, aliases, tainted, table, analysis)
  end

  defp targets_table?(list, schemas, aliases, tainted, table, analysis, clauses) when is_list(list) do
    Enum.any?(list, &targets_table?(&1, schemas, aliases, tainted, table, analysis, clauses))
  end

  defp targets_table?(tuple, schemas, aliases, tainted, table, analysis, clauses) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&targets_table?(&1, schemas, aliases, tainted, table, analysis, clauses))
  end

  defp targets_table?(_literal, _schemas, _aliases, _tainted, _table, _analysis, _clauses), do: false

  defp call_returns_target?(name, arguments, clauses, schemas, aliases, tainted, table, analysis) do
    local_call_returns_target?(clauses, analysis, name, length(arguments)) or
      kernel_constructor_target?(name, arguments, schemas, aliases, tainted, table, analysis, clauses) or
      query_builder_target?(name, arguments, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp kernel_constructor_target?(name, [first | _rest], schemas, aliases, tainted, table, analysis, clauses)
       when name in [:struct, :struct!] do
    targets_table?(first, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp kernel_constructor_target?(_name, _arguments, _schemas, _aliases, _tainted, _table, _analysis, _clauses), do: false

  defp query_builder_target?(:from, [source | options], schemas, aliases, tainted, table, analysis, clauses) do
    from_query_result_targets_table?(
      source,
      List.flatten(options),
      schemas,
      aliases,
      tainted,
      table,
      analysis,
      clauses
    )
  end

  defp query_builder_target?(:select, arguments, schemas, aliases, tainted, table, analysis, clauses) do
    select_query_result_targets_table?(
      arguments,
      schemas,
      aliases,
      tainted,
      table,
      analysis,
      clauses
    )
  end

  defp query_builder_target?(name, [query | _arguments], schemas, aliases, tainted, table, analysis, clauses)
       when name in [:distinct, :exclude, :group_by, :join, :limit, :lock, :offset, :order_by, :preload, :where] do
    targets_table?(query, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp query_builder_target?(_name, _arguments, _schemas, _aliases, _tainted, _table, _analysis, _clauses), do: false

  @query_join_keys [
    :join,
    :inner_join,
    :left_join,
    :right_join,
    :full_join,
    :cross_join,
    :inner_lateral_join,
    :left_lateral_join,
    :cross_lateral_join
  ]

  defp from_query_result_targets_table?(source, options, schemas, aliases, tainted, table, analysis, clauses) do
    primary_target? =
      query_source_expression_targets_table?(
        source,
        schemas,
        aliases,
        tainted,
        table,
        analysis,
        clauses
      )

    case Keyword.fetch(options, :select) do
      :error ->
        primary_target?

      {:ok, selection} ->
        primary_bindings = query_binding_targets(source, primary_target?)
        primary_modules = query_binding_modules(source, aliases)

        bindings =
          Map.merge(
            primary_bindings,
            join_binding_targets(
              options,
              primary_modules,
              schemas,
              aliases
            )
          )

        selected_query_value_targets_table?(selection, bindings)
    end
  end

  defp select_query_result_targets_table?(arguments, schemas, aliases, tainted, table, analysis, clauses) do
    case arguments do
      [query, bindings, selection] ->
        query_target? = targets_table?(query, schemas, aliases, tainted, table, analysis, clauses)

        bindings
        |> select_binding_targets(query_target?)
        |> then(&selected_query_value_targets_table?(selection, &1))

      [query, selection] ->
        query_target? = targets_table?(query, schemas, aliases, tainted, table, analysis, clauses)

        case selection do
          {name, _, context} when is_atom(name) and is_atom(context) -> query_target?
          _selection -> false
        end

      _arguments ->
        false
    end
  end

  defp query_source_expression_targets_table?(
         {:in, _, [_binding, source]},
         schemas,
         aliases,
         tainted,
         table,
         analysis,
         clauses
       ) do
    targets_table?(source, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp query_source_expression_targets_table?(source, schemas, aliases, tainted, table, analysis, clauses) do
    targets_table?(source, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp query_binding_targets({:in, _, [binding, _source]}, target?), do: Map.new(variable_names(binding), &{&1, target?})

  defp query_binding_targets(bindings, target?) when is_list(bindings),
    do: Map.new(variable_names(bindings), &{&1, target?})

  defp query_binding_targets(_source, _target?), do: %{}

  defp query_binding_modules({:in, _, [binding, source]}, aliases) do
    modules = query_source_modules(source, %{}, aliases)
    Map.new(variable_names(binding), &{&1, modules})
  end

  defp query_binding_modules(_source, _aliases), do: %{}

  # A prebuilt Ecto query does not retain binding provenance in its variable
  # AST. Its first binding is the query's selected source; selecting any later
  # binding must therefore fail closed for every mapped table visible to the
  # source scan. This can create a reviewable false positive, but it prevents a
  # joined record selected from an opaque query from escaping the ratchet.
  defp select_binding_targets(bindings, query_target?) when is_list(bindings) do
    bindings
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {binding, index}, targets ->
      target? = if index == 0 and not keyword_binding?(binding), do: query_target?, else: true
      Map.merge(targets, Map.new(variable_names(binding), &{&1, target?}))
    end)
  end

  defp select_binding_targets(_bindings, _query_target?), do: %{}

  defp keyword_binding?({name, _binding}) when is_atom(name), do: true
  defp keyword_binding?(_binding), do: false

  defp join_binding_targets(options, primary_modules, schemas, aliases) do
    {targets, _modules} =
      Enum.reduce(options, {%{}, primary_modules}, fn
        {key, {:in, _, [binding, source]}}, {targets, binding_modules} when key in @query_join_keys ->
          source_modules = query_source_modules(source, binding_modules, aliases)

          target? =
            case source_modules do
              :unresolved -> true
              modules -> Enum.any?(modules, &(&1 in schemas))
            end

          source_modules = if source_modules == :unresolved, do: [], else: source_modules

          {
            Map.merge(targets, Map.new(variable_names(binding), &{&1, target?})),
            Map.merge(binding_modules, Map.new(variable_names(binding), &{&1, source_modules}))
          }

        _option, state ->
          state
      end)

    targets
  end

  defp query_source_modules({:__aliases__, _, segments}, _binding_modules, aliases) do
    segments
    |> expanded_modules(aliases)
    |> Enum.map(&module_name/1)
    |> Enum.uniq()
  end

  defp query_source_modules({:assoc, _, [parent, association]}, binding_modules, _aliases) when is_atom(association) do
    with {name, _, context} when is_atom(name) and is_atom(context) <- parent,
         parent_modules when is_list(parent_modules) and parent_modules != [] <- Map.get(binding_modules, name),
         related when related != [] <- association_related_modules(parent_modules, association) do
      related
    else
      _unresolved -> :unresolved
    end
  end

  defp query_source_modules(_source, _binding_modules, _aliases), do: :unresolved

  defp association_related_modules(parent_modules, association) do
    parent_modules
    |> Enum.flat_map(fn module_name ->
      with {:ok, module} <- existing_module(module_name),
           {:module, ^module} <- Code.ensure_loaded(module),
           true <- function_exported?(module, :__schema__, 2),
           association_metadata when not is_nil(association_metadata) <- module.__schema__(:association, association),
           related when is_atom(related) <- Map.get(association_metadata, :related) do
        [related |> Atom.to_string() |> String.trim_leading("Elixir.")]
      else
        _unresolved -> []
      end
    end)
    |> Enum.uniq()
  end

  defp existing_module(module_name) do
    {:ok, Module.safe_concat(String.split(module_name, "."))}
  rescue
    ArgumentError -> :error
  end

  defp selected_query_value_targets_table?({name, _, context}, bindings) when is_atom(name) and is_atom(context),
    do: Map.get(bindings, name, false)

  defp selected_query_value_targets_table?({constructor, _, [base | _fields]}, bindings)
       when constructor in [:struct, :struct!], do: selected_query_value_targets_table?(base, bindings)

  # A field selection is a scalar even when its receiver is a mapped record.
  # Treating `select: record.id` as the record itself is what made unrelated
  # joined schemas appear to be written by later Repo calls.
  defp selected_query_value_targets_table?({{:., _, [_receiver, _field]}, _, []}, _bindings), do: false

  defp selected_query_value_targets_table?({:{}, _, values}, bindings),
    do: Enum.any?(values, &selected_query_value_targets_table?(&1, bindings))

  defp selected_query_value_targets_table?({:%{}, _, pairs}, bindings) do
    Enum.any?(pairs, fn
      {:|, _, [base, _updates]} -> selected_query_value_targets_table?(base, bindings)
      {_key, value} -> selected_query_value_targets_table?(value, bindings)
      value -> selected_query_value_targets_table?(value, bindings)
    end)
  end

  defp selected_query_value_targets_table?(values, bindings) when is_list(values),
    do: Enum.any?(values, &selected_query_value_targets_table?(&1, bindings))

  defp selected_query_value_targets_table?(_selection, _bindings), do: false

  defp target_context(clauses, schemas, aliases, tainted, table, analysis) do
    %{
      aliases: aliases,
      analysis: analysis,
      clauses: clauses,
      repo_variables: Map.get(analysis, :repo_variables, MapSet.new()),
      schemas: schemas,
      table: table,
      tainted: tainted
    }
  end

  defp remote_call_returns_target?(receiver, function, arguments, context) do
    modules = receiver_modules(receiver, context.aliases)
    first = Enum.at(arguments, 0)

    cond do
      repo_read_call?(modules, function) or
          injected_repo_read_call?(receiver, function, context.repo_variables) ->
        target_argument?(first, context)

      changeset_call?(modules, function) ->
        target_argument?(first, context)

      map_value_call?(modules, function) ->
        target_argument?(first, context)

      enumerable_module?(modules) ->
        enumerable_result_targets_table?(function, arguments, context)

      module_ast_targets_table?(receiver, context.schemas, context.aliases) and changeset_function?(function) ->
        true

      true ->
        false
    end
  end

  defp repo_read_call?(modules, function),
    do: repo_module?(modules) and function in [:all, :get, :get!, :get_by, :get_by!, :one, :one!, :preload]

  defp injected_repo_read_call?({name, _, context}, function, repo_variables) when is_atom(name) and is_atom(context),
    do: MapSet.member?(repo_variables, name) and function in [:all, :get, :get!, :get_by, :get_by!, :one, :one!, :preload]

  defp injected_repo_read_call?(_receiver, _function, _repo_variables), do: false

  defp changeset_call?(modules, function),
    do: module_named?(modules, "Ecto.Changeset") and function in @changeset_passthrough_functions

  defp map_value_call?(modules, function),
    do:
      module_named?(modules, "Map") and
        function in [:fetch, :fetch!, :get, :get_lazy, :new, :put, :replace, :take, :values]

  defp enumerable_module?(modules), do: Enum.any?(modules, &(module_name(&1) in ["Enum", "Stream"]))
  defp module_named?(modules, expected), do: Enum.any?(modules, &(module_name(&1) == expected))

  defp enumerable_result_targets_table?(function, arguments, context) do
    collection_target? = arguments |> Enum.at(0) |> target_argument?(context)

    cond do
      function in [:filter, :reject, :sort, :sort_by, :take, :take_while, :uniq, :uniq_by] ->
        collection_target?

      function in [:find, :find_value] ->
        collection_target?

      function in [:flat_map, :map] ->
        arguments
        |> List.last()
        |> callback_returns_target?(
          context.schemas,
          context.aliases,
          context.tainted,
          context.table,
          context.analysis,
          context.clauses
        )

      true ->
        false
    end
  end

  defp callback_returns_target?({:&, _, [body]}, schemas, aliases, tainted, table, analysis, clauses) do
    targets_table?(body, schemas, aliases, tainted, table, analysis, clauses)
  end

  defp callback_returns_target?({:fn, _, callback_clauses}, schemas, aliases, tainted, table, analysis, clauses) do
    Enum.any?(callback_clauses, fn
      {:->, _, [_parameters, body]} ->
        clause_returns_target?(body, schemas, aliases, tainted, table, analysis, clauses)

      _node ->
        false
    end)
  end

  defp callback_returns_target?(_callback, _schemas, _aliases, _tainted, _table, _analysis, _clauses), do: false

  defp changeset_function?(function) do
    function == :changeset or String.ends_with?(Atom.to_string(function), "_changeset")
  end

  defp receiver_modules({:__aliases__, _, segments}, aliases), do: expanded_modules(segments, aliases)
  defp receiver_modules(_receiver, _aliases), do: []

  defp module_ast_targets_table?({:__aliases__, _, segments}, schemas, aliases),
    do: module_targets_table?(segments, schemas, aliases)

  defp module_ast_targets_table?(_module, _schemas, _aliases), do: false

  defp module_targets_table?(segments, schemas, aliases) do
    segments
    |> expanded_modules(aliases)
    |> Enum.any?(&(module_name(&1) in schemas))
  end

  defp persistence_targets_table?(ast, schemas, aliases, tainted, table, analysis, clauses, attributes) do
    targets_table?(ast, schemas, aliases, tainted, table, analysis, clauses) or
      contains_table_literal?(ast, table) or
      contains_table_attribute?(ast, attributes, table)
  end

  defp contains_table_literal?(ast, table) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        ^table = node, _found? -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp contains_table_attribute?(ast, attributes, table) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{name, _, _context}]} = node, found? when is_atom(name) ->
          {node, found? or Map.get(attributes, name) == table}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp local_call_returns_target?(clauses, analysis, name, arity) do
    clauses
    |> matching_clauses(name, arity)
    |> Enum.any?(&MapSet.member?(analysis.returns, &1.id))
  end

  defp variable_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, context} = node, names when is_atom(name) and is_atom(context) ->
          {node, MapSet.put(names, name)}

        node, names ->
          {node, names}
      end)

    names
  end

  defp function_identity(visibility, {:when, _, [head | _guards]}), do: function_identity(visibility, head)

  defp function_identity(visibility, {name, _, arguments}) when is_atom(name) do
    "#{visibility} #{name}/#{length(arguments || [])}"
  end

  defp function_identity(visibility, _head), do: "#{visibility} unknown"

  defp alias_bindings(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn node, aliases ->
        aliases =
          Enum.reduce(alias_targets(node), aliases, fn {local, target}, acc ->
            Map.update(acc, local, [target], &[target | &1])
          end)

        {node, aliases}
      end)

    aliases
  end

  defp alias_targets({:alias, _, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, children}]}) do
    for {:__aliases__, _, suffix} <- children do
      target = module_parts(prefix ++ suffix)
      {List.last(target), target}
    end
  end

  defp alias_targets({:alias, _, [{:__aliases__, _, segments}, options]}) when is_list(options) do
    target = module_parts(segments)

    local =
      case Keyword.get(options, :as) do
        {:__aliases__, _, as_segments} -> as_segments |> module_parts() |> List.last()
        _other -> List.last(target)
      end

    [{local, target}]
  end

  defp alias_targets({:alias, _, [{:__aliases__, _, segments}]}) do
    target = module_parts(segments)
    [{List.last(target), target}]
  end

  defp alias_targets(_node), do: []

  defp imported_modules(ast, aliases) do
    {_ast, imports} =
      Macro.prewalk(ast, [], fn
        {:import, _, [{:__aliases__, _, segments} | rest]} = node, imports ->
          options = import_options(rest)

          specs =
            segments
            |> expanded_modules(aliases)
            |> Enum.map(fn module ->
              %{
                module: module_name(module),
                only: import_filter(Keyword.get(options, :only)),
                except: import_filter(Keyword.get(options, :except))
              }
            end)

          {node, specs ++ imports}

        node, imports ->
          {node, imports}
      end)

    Enum.uniq(imports)
  end

  defp import_options([options]) when is_list(options), do: options
  defp import_options(_rest), do: []

  defp import_filter(entries) when is_list(entries), do: MapSet.new(entries)
  defp import_filter(kind) when kind in [:functions, :macros], do: kind
  defp import_filter(_entries), do: nil

  defp imported_function?(imports, module, operation, arity) do
    case Enum.find(imports, &match?(%{module: ^module}, &1)) do
      %{only: only, except: except} ->
        import_includes?(only, operation, arity) and
          not import_excludes?(except, operation, arity)

      nil ->
        false
    end
  end

  defp import_includes?(nil, _operation, _arity), do: true
  defp import_includes?(:functions, _operation, _arity), do: true
  defp import_includes?(:macros, _operation, _arity), do: false
  defp import_includes?(entries, operation, arity), do: MapSet.member?(entries, {operation, arity})

  defp import_excludes?(nil, _operation, _arity), do: false
  defp import_excludes?(kind, _operation, _arity) when kind in [:functions, :macros], do: false
  defp import_excludes?(entries, operation, arity), do: MapSet.member?(entries, {operation, arity})

  defp expanded_modules(segments, aliases) do
    segments
    |> module_parts()
    |> expand_module_parts(aliases, MapSet.new())
    |> Enum.uniq()
  end

  defp expand_module_parts([], _aliases, _seen), do: []

  defp expand_module_parts([first | rest] = parts, aliases, seen) do
    if MapSet.member?(seen, parts) do
      [parts]
    else
      case Map.get(aliases, first, []) do
        [] ->
          [parts]

        targets ->
          Enum.flat_map(targets, &expand_module_parts(&1 ++ rest, aliases, MapSet.put(seen, parts)))
      end
    end
  end

  defp repo_module?(modules) do
    modules
    |> Enum.map(&module_name/1)
    |> Enum.uniq() == ["Storyarn.Repo"]
  end

  defp transparent_write_delegate(modules, function, arity) do
    module_names = MapSet.new(modules, &module_name/1)

    Enum.find(@transparent_write_delegates, fn delegate ->
      MapSet.member?(module_names, delegate.module) and
        delegate.function == function and delegate.arity == arity
    end)
  end

  defp ecto_adapters_sql_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Ecto.Adapters.SQL"))

  defp repo_ast?(module, aliases, repo_variables)

  defp repo_ast?({:__aliases__, _, segments}, aliases, _repo_variables),
    do: repo_module?(expanded_modules(segments, aliases))

  defp repo_ast?({name, _, context}, _aliases, repo_variables) when is_atom(name) and is_atom(context),
    do: MapSet.member?(repo_variables, name)

  defp repo_ast?(_module, _aliases, _repo_variables), do: false

  defp multi_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Ecto.Multi"))

  defp quoted!(source, path), do: Code.string_to_quoted!(source, file: path, columns: true)

  defp module_parts(segments), do: Enum.map(segments, &Atom.to_string/1)
  defp module_name([part | _] = parts) when is_binary(part), do: Enum.join(parts, ".")
  defp module_name(segments), do: Enum.join(module_parts(segments), ".")
end
