defmodule Storyarn.Versioning.ProjectSnapshotReset do
  @moduledoc """
  Environment- and workspace-scoped reset for pre-canonical project snapshots.

  The generated JSON plan is the durable audit and retry receipt. Execution
  accepts only the exact inventory recorded by a dry run, rejects new or
  replaced objects, checkpoints the shrinking inventory, and deletes database
  rows only after every scoped storage prefix re-lists empty.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotStorage

  @format "storyarn.project_snapshot_reset"
  @format_version 1
  @page_size 1_000
  @delete_batch_size 100
  @default_max_objects 250_000
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @blob_filename_regex ~r/\A[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z/
  @plan_keys Enum.sort(~w(
                 attempt_count authorization_digest completed_at environment format format_version
                 entity_version_row_ids inventory_digest last_error_code objects prefixes prepared_at
                 project_ids remaining_storage_keys snapshot_row_ids status workspace_id
               ))

  @type plan :: map()

  @doc "Builds a read-only exact reset plan for one workspace and environment."
  @spec prepare(pos_integer(), String.t(), keyword()) :: {:ok, plan()} | {:error, term()}
  def prepare(workspace_id, expected_environment, opts \\ [])

  def prepare(workspace_id, expected_environment, opts)
      when is_integer(workspace_id) and workspace_id > 0 and is_binary(expected_environment) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())
    max_objects = Keyword.get(opts, :max_objects, @default_max_objects)

    with {:ok, environment} <- verify_environment(expected_environment, opts),
         :ok <- validate_max_objects(max_objects),
         :ok <- ensure_workspace_exists(repo, workspace_id),
         {:ok, project_ids, snapshot_rows, entity_version_rows} <- load_scope(repo, workspace_id, max_objects),
         :ok <- validate_snapshot_row_identities(snapshot_rows),
         :ok <- validate_entity_version_row_identities(entity_version_rows),
         prefixes = reset_prefixes(project_ids),
         {:ok, objects} <- list_exact_inventory(adapter, prefixes, max_objects),
         :ok <- validate_objects(objects, project_ids),
         now = TimeHelpers.now(),
         plan =
           build_plan(
             environment,
             workspace_id,
             project_ids,
             snapshot_rows,
             entity_version_rows,
             prefixes,
             objects,
             now
           ),
         :ok <- validate_plan(plan) do
      {:ok, plan}
    end
  end

  def prepare(_workspace_id, _expected_environment, _opts), do: {:error, :invalid_snapshot_reset_scope}

  @doc "Executes or resumes one previously prepared exact reset plan."
  @spec execute(plan(), String.t(), keyword()) :: {:ok, plan()} | {:error, term(), plan()}
  def execute(plan, confirmation_digest, opts \\ [])

  def execute(plan, confirmation_digest, opts) when is_map(plan) and is_binary(confirmation_digest) and is_list(opts) do
    repo = Keyword.get(opts, :repo, Repo)
    adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())
    checkpoint = Keyword.get(opts, :checkpoint, fn _plan -> :ok end)

    with :ok <- validate_plan(plan),
         :ok <- verify_confirmation(plan, confirmation_digest),
         {:ok, environment} <- verify_environment(plan["environment"], opts),
         {:ok, authorization_digest} <- authorize_execution(opts) do
      execute_authorized_plan(plan, environment, authorization_digest, repo, adapter, checkpoint)
    else
      {:error, reason} -> {:error, reason, plan}
    end
  end

  def execute(plan, _confirmation_digest, _opts), do: {:error, :invalid_snapshot_reset_plan, plan}

  defp execute_authorized_plan(
         %{"status" => "completed"} = plan,
         _environment,
         _authorization,
         repo,
         adapter,
         _checkpoint
       ) do
    case final_zero_state(repo, adapter, plan) do
      :complete -> {:ok, plan}
      :incomplete -> {:error, :snapshot_reset_completed_state_changed, plan}
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp execute_authorized_plan(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    case final_zero_state(repo, adapter, plan) do
      :complete -> recover_completed_plan(plan, environment, authorization_digest, checkpoint)
      :incomplete -> execute_pending_plan(plan, environment, authorization_digest, repo, adapter, checkpoint)
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp recover_completed_plan(plan, environment, authorization_digest, checkpoint) do
    running = mark_running(plan, authorization_digest)

    case checkpoint_plan(checkpoint, running) do
      :ok -> complete_execution(running, environment, checkpoint)
      {:error, reason} -> fail_execution(running, {:snapshot_reset_checkpoint_failed, reason}, checkpoint)
    end
  end

  defp execute_pending_plan(plan, environment, authorization_digest, repo, adapter, checkpoint) do
    with :ok <- revalidate_database_scope(repo, plan),
         :ok <- revalidate_storage_scope(adapter, plan) do
      running = mark_running(plan, authorization_digest)
      execute_running_plan(running, environment, repo, adapter, checkpoint)
    else
      {:error, reason} -> {:error, reason, plan}
    end
  end

  defp mark_running(plan, authorization_digest) do
    plan
    |> Map.put("status", "running")
    |> Map.put("attempt_count", plan["attempt_count"] + 1)
    |> Map.put("authorization_digest", authorization_digest)
    |> Map.put("last_error_code", nil)
  end

  defp execute_running_plan(running, environment, repo, adapter, checkpoint) do
    with :ok <- checkpoint_plan(checkpoint, running),
         {:ok, storage_complete} <- delete_inventory(adapter, running, checkpoint),
         :ok <- verify_prefixes_empty(adapter, storage_complete["prefixes"]),
         :ok <- delete_snapshot_rows(repo, storage_complete) do
      complete_execution(storage_complete, environment, checkpoint)
    else
      {:error, reason, failed_plan} -> {:error, reason, failed_plan}
      {:error, reason} -> fail_execution(running, reason, checkpoint)
    end
  end

  defp complete_execution(storage_complete, environment, checkpoint) do
    completed =
      storage_complete
      |> Map.put("status", "completed")
      |> Map.put("completed_at", DateTime.to_iso8601(TimeHelpers.now()))

    case checkpoint_plan(checkpoint, completed) do
      :ok ->
        emit_reset_stop(completed, environment)
        {:ok, completed}

      {:error, reason} ->
        {:error, {:snapshot_reset_checkpoint_failed, reason}, completed}
    end
  end

  @doc false
  def validate_plan(
        %{
          "format" => @format,
          "format_version" => @format_version,
          "environment" => environment,
          "workspace_id" => workspace_id,
          "project_ids" => project_ids,
          "snapshot_row_ids" => row_ids,
          "entity_version_row_ids" => entity_version_row_ids,
          "prefixes" => prefixes,
          "objects" => objects,
          "remaining_storage_keys" => remaining,
          "inventory_digest" => digest,
          "status" => status,
          "attempt_count" => attempt_count
        } = plan
      ) do
    valid? =
      with true <- Enum.sort(Map.keys(plan)) == @plan_keys,
           true <- valid_environment?(environment),
           true <- is_integer(workspace_id) and workspace_id > 0,
           true <- positive_unique_integers?(project_ids),
           true <- positive_unique_integers?(row_ids),
           true <- positive_unique_integers?(entity_version_row_ids),
           true <- is_list(prefixes) and prefixes == reset_prefixes(project_ids),
           true <- is_list(objects) and Enum.all?(objects, &valid_plan_object?/1),
           true <- objects == Enum.sort_by(objects, & &1["key"]),
           true <- objects == Enum.uniq_by(objects, & &1["key"]),
           :ok <- validate_objects(objects, project_ids),
           true <- is_list(remaining) and Enum.all?(remaining, &is_binary/1),
           true <- remaining == Enum.uniq(remaining),
           object_keys = MapSet.new(objects, & &1["key"]),
           true <- Enum.all?(remaining, &MapSet.member?(object_keys, &1)),
           true <- is_binary(digest) and Regex.match?(@sha256_regex, digest),
           true <- Plug.Crypto.secure_compare(digest, inventory_digest(plan)),
           true <- status in ["prepared", "running", "failed", "completed"],
           true <- is_integer(attempt_count) and attempt_count >= 0,
           true <- valid_plan_state_metadata?(plan) do
        true
      else
        _invalid -> false
      end

    if valid?, do: :ok, else: {:error, :invalid_snapshot_reset_plan}
  end

  def validate_plan(_plan), do: {:error, :invalid_snapshot_reset_plan}

  defp valid_environment?(environment) when is_binary(environment) do
    byte_size(environment) in 1..128 and String.trim(environment) == environment and
      String.match?(environment, ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
  end

  defp valid_environment?(_environment), do: false

  defp valid_plan_state_metadata?(plan) do
    valid_timestamp?(plan["prepared_at"]) and valid_error_code?(plan["last_error_code"]) and
      valid_plan_status_metadata?(
        plan["status"],
        plan["attempt_count"],
        plan["authorization_digest"],
        plan["completed_at"]
      )
  end

  defp valid_plan_status_metadata?("prepared", 0, nil, nil), do: true

  defp valid_plan_status_metadata?(status, attempt_count, authorization_digest, nil)
       when status in ["running", "failed"] and attempt_count > 0, do: valid_digest?(authorization_digest)

  defp valid_plan_status_metadata?("completed", attempt_count, authorization_digest, completed_at) when attempt_count > 0,
    do: valid_digest?(authorization_digest) and valid_timestamp?(completed_at)

  defp valid_plan_status_metadata?(_status, _attempt_count, _authorization_digest, _completed_at), do: false

  defp valid_timestamp?(value) when is_binary(value), do: match?({:ok, _datetime, 0}, DateTime.from_iso8601(value))
  defp valid_timestamp?(_value), do: false

  defp valid_error_code?(nil), do: true
  defp valid_error_code?(value) when is_binary(value), do: byte_size(value) in 1..160
  defp valid_error_code?(_value), do: false

  defp valid_digest?(value), do: is_binary(value) and Regex.match?(@sha256_regex, value)

  defp verify_environment(expected_environment, opts) do
    current = Keyword.get(opts, :current_environment) || System.get_env("STORYARN_DEPLOYMENT_ENVIRONMENT")

    cond do
      not is_binary(expected_environment) or String.trim(expected_environment) == "" ->
        {:error, :snapshot_reset_environment_required}

      not is_binary(current) or String.trim(current) == "" ->
        {:error, :snapshot_reset_current_environment_unconfigured}

      current != expected_environment ->
        {:error, :snapshot_reset_environment_mismatch}

      true ->
        {:ok, current}
    end
  end

  defp authorize_execution(opts) do
    expected = Keyword.get(opts, :expected_authorization) || System.get_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION")
    supplied = Keyword.get(opts, :authorization) || expected

    if is_binary(expected) and byte_size(expected) >= 32 and is_binary(supplied) and byte_size(supplied) >= 32 and
         Plug.Crypto.secure_compare(expected, supplied) do
      {:ok, sha256(expected)}
    else
      {:error, :snapshot_reset_not_authorized}
    end
  end

  defp verify_confirmation(plan, confirmation_digest) do
    if Regex.match?(@sha256_regex, confirmation_digest) and
         Plug.Crypto.secure_compare(plan["inventory_digest"], confirmation_digest),
       do: :ok,
       else: {:error, :snapshot_reset_inventory_confirmation_mismatch}
  end

  defp validate_max_objects(max_objects) when is_integer(max_objects) and max_objects > 0, do: :ok
  defp validate_max_objects(_max_objects), do: {:error, :invalid_snapshot_reset_limit}

  defp ensure_workspace_exists(repo, workspace_id) do
    case repo.query("SELECT 1 FROM workspaces WHERE id = $1 LIMIT 1", [workspace_id]) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, _result} -> {:error, :snapshot_reset_workspace_not_found}
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp load_scope(repo, workspace_id, max_rows) do
    projects_query = "SELECT id FROM projects WHERE workspace_id = $1 ORDER BY id LIMIT $2"

    rows_query = """
    SELECT ps.id, ps.project_id, to_jsonb(ps)
    FROM project_snapshots ps
    JOIN projects p ON p.id = ps.project_id
    WHERE p.workspace_id = $1
    ORDER BY ps.id
    LIMIT $2
    """

    entity_versions_query = """
    SELECT ev.id, ev.project_id, ev.entity_type, ev.entity_id, ev.version_number,
           ev.storage_key, ev.snapshot_size_bytes
    FROM entity_versions ev
    JOIN projects p ON p.id = ev.project_id
    WHERE p.workspace_id = $1
    ORDER BY ev.id
    LIMIT $2
    """

    query_limit = max_rows + 1

    with {:ok, %{rows: project_rows}} <- repo.query(projects_query, [workspace_id, query_limit]),
         {:ok, %{rows: snapshot_rows}} <- repo.query(rows_query, [workspace_id, query_limit]),
         {:ok, %{rows: entity_version_rows}} <- repo.query(entity_versions_query, [workspace_id, query_limit]),
         true <- Enum.all?([project_rows, snapshot_rows, entity_version_rows], &(length(&1) <= max_rows)) do
      project_ids = Enum.map(project_rows, fn [id] -> id end)

      snapshot_rows =
        Enum.map(snapshot_rows, fn [id, project_id, data] -> %{"id" => id, "project_id" => project_id, "data" => data} end)

      entity_version_rows =
        Enum.map(entity_version_rows, fn [id, project_id, entity_type, entity_id, version_number, storage_key, size] ->
          %{
            "id" => id,
            "project_id" => project_id,
            "entity_type" => entity_type,
            "entity_id" => entity_id,
            "version_number" => version_number,
            "storage_key" => storage_key,
            "size" => size
          }
        end)

      {:ok, project_ids, snapshot_rows, entity_version_rows}
    else
      false -> {:error, :snapshot_reset_database_inventory_limit_exceeded}
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp validate_snapshot_row_identities(rows) do
    if Enum.all?(rows, &valid_row_identity?/1),
      do: :ok,
      else: {:error, :unsafe_snapshot_reset_row_identity}
  end

  defp validate_entity_version_row_identities(rows) do
    if Enum.all?(rows, &valid_entity_version_row_identity?/1),
      do: :ok,
      else: {:error, :unsafe_entity_version_reset_row_identity}
  end

  defp valid_row_identity?(%{"id" => id, "project_id" => project_id, "data" => data})
       when is_integer(id) and id > 0 and is_integer(project_id) and project_id > 0 and is_map(data) do
    keys = Enum.reject([data["storage_key"], data["project_storage_key"], data["manifest_storage_key"]], &is_nil/1)

    prefix = data["object_prefix"]

    Enum.all?(keys, &valid_reset_key_for_project?(&1, project_id)) and
      (is_nil(prefix) or valid_object_set_prefix?(prefix, project_id))
  end

  defp valid_row_identity?(_row), do: false

  defp valid_entity_version_row_identity?(%{
         "id" => id,
         "project_id" => project_id,
         "entity_type" => entity_type,
         "entity_id" => entity_id,
         "version_number" => version_number,
         "storage_key" => storage_key,
         "size" => size
       })
       when is_integer(id) and id > 0 and is_integer(size) and size >= 0 do
    SnapshotStorage.entity_key?(storage_key, project_id, entity_type, entity_id, version_number)
  end

  defp valid_entity_version_row_identity?(_row), do: false

  defp reset_prefixes(project_ids) do
    project_ids
    |> Enum.flat_map(fn project_id ->
      root = "projects/#{project_id}/snapshots"

      [
        "#{root}/project/",
        "#{root}/flow/",
        "#{root}/object-sets/v1/ready/",
        "#{root}/object-sets/v1/staging/",
        "#{root}/scene/",
        "#{root}/sheet/"
      ]
    end)
    |> Enum.sort()
  end

  defp list_exact_inventory(adapter, prefixes, max_objects) do
    prefixes
    |> Enum.reduce_while({:ok, [], 0}, fn prefix, {:ok, objects, count} ->
      case list_prefix_pages(adapter, prefix, nil, objects, count, max_objects, MapSet.new()) do
        {:ok, listed, listed_count} -> {:cont, {:ok, listed, listed_count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed_objects, _count} ->
        objects = Enum.reverse(reversed_objects)
        objects = Enum.sort_by(objects, & &1["key"])

        if objects == Enum.uniq_by(objects, & &1["key"]),
          do: {:ok, objects},
          else: {:error, :duplicate_snapshot_reset_object}

      error ->
        error
    end
  end

  defp list_prefix_pages(adapter, prefix, cursor, objects, object_count, max_objects, seen_cursors) do
    with {:ok, %{objects: page, cursor: next_cursor}} <- safe_list_prefix(adapter, prefix, cursor),
         true <- is_list(page) and length(page) <= @page_size,
         {:ok, normalized} <- normalize_page(page, prefix),
         combined_count = object_count + length(normalized),
         true <- combined_count <= max_objects do
      combined = Enum.reduce(normalized, objects, &[&1 | &2])

      cond do
        is_nil(next_cursor) ->
          {:ok, combined, combined_count}

        not is_binary(next_cursor) or next_cursor == "" ->
          {:error, :invalid_snapshot_reset_cursor}

        normalized == [] ->
          {:error, :empty_snapshot_reset_page_with_cursor}

        MapSet.member?(seen_cursors, next_cursor) ->
          {:error, :repeated_snapshot_reset_cursor}

        true ->
          list_prefix_pages(
            adapter,
            prefix,
            next_cursor,
            combined,
            combined_count,
            max_objects,
            MapSet.put(seen_cursors, next_cursor)
          )
      end
    else
      false -> {:error, :snapshot_reset_inventory_limit_exceeded}
      {:error, reason} -> {:error, {:snapshot_reset_storage_list_failed, reason}}
      _invalid -> {:error, :invalid_snapshot_reset_storage_page}
    end
  end

  defp safe_list_prefix(adapter, prefix, cursor) do
    adapter.list_prefix(prefix, limit: @page_size, cursor: cursor)
  rescue
    _exception -> {:error, :storage_list_failed}
  catch
    _kind, _reason -> {:error, :storage_list_failed}
  end

  defp normalize_page(page, prefix) do
    normalized =
      Enum.map(page, fn
        %{key: key, size: size} -> %{"key" => key, "size" => size}
        %{"key" => key, "size" => size} -> %{"key" => key, "size" => size}
        _invalid -> nil
      end)

    if Enum.all?(normalized, fn
         %{"key" => key, "size" => size} ->
           is_binary(key) and String.starts_with?(key, prefix) and is_integer(size) and size >= 0

         _invalid ->
           false
       end),
       do: {:ok, normalized},
       else: {:error, :invalid_snapshot_reset_storage_page}
  end

  defp validate_objects(objects, project_ids) do
    if Enum.all?(objects, fn %{"key" => key} -> Enum.any?(project_ids, &valid_reset_key_for_project?(key, &1)) end),
      do: :ok,
      else: {:error, :unsafe_snapshot_reset_object}
  end

  defp valid_reset_key_for_project?(key, project_id) when is_binary(key) do
    legacy_prefix = "projects/#{project_id}/snapshots/project/"
    object_set_root = "projects/#{project_id}/snapshots/object-sets/v1/"
    entity_version_root = "projects/#{project_id}/snapshots/"

    cond do
      String.starts_with?(key, legacy_prefix) ->
        relative = String.replace_prefix(key, legacy_prefix, "")
        relative != "" and Storage.canonical_key?(relative) and String.ends_with?(relative, ".json.gz")

      String.starts_with?(key, object_set_root) ->
        valid_object_set_key?(String.replace_prefix(key, object_set_root, ""))

      String.starts_with?(key, entity_version_root) ->
        valid_entity_version_key?(String.replace_prefix(key, entity_version_root, ""))

      true ->
        false
    end
  end

  defp valid_reset_key_for_project?(_key, _project_id), do: false

  defp valid_object_set_prefix?(prefix, project_id) when is_binary(prefix) do
    root = "projects/#{project_id}/snapshots/object-sets/v1/ready/"
    token = String.replace_prefix(prefix, root, "")
    String.starts_with?(prefix, root) and Regex.match?(@token_regex, token)
  end

  defp valid_object_set_prefix?(_prefix, _project_id), do: false

  defp valid_object_set_key?(relative) do
    case String.split(relative, "/", parts: 3) do
      [state, token, path] when state in ["ready", "staging"] ->
        Regex.match?(@token_regex, token) and valid_object_set_relative_path?(path)

      _invalid ->
        false
    end
  end

  defp valid_object_set_relative_path?(path) when path in ["project.json", "manifest.json"], do: true

  defp valid_object_set_relative_path?("blobs/" <> filename), do: Regex.match?(@blob_filename_regex, filename)

  defp valid_object_set_relative_path?(_path), do: false

  defp valid_entity_version_key?(relative) do
    Regex.match?(~r/\A(?:sheet|flow|scene)\/[1-9][0-9]*\/[1-9][0-9]*-[0-9a-f]{16}\.json\.gz\z/, relative)
  end

  defp build_plan(environment, workspace_id, project_ids, snapshot_rows, entity_version_rows, prefixes, objects, now) do
    plan = %{
      "format" => @format,
      "format_version" => @format_version,
      "environment" => environment,
      "workspace_id" => workspace_id,
      "project_ids" => project_ids,
      "snapshot_row_ids" => Enum.map(snapshot_rows, & &1["id"]),
      "entity_version_row_ids" => Enum.map(entity_version_rows, & &1["id"]),
      "prefixes" => prefixes,
      "objects" => objects,
      "remaining_storage_keys" => Enum.map(objects, & &1["key"]),
      "inventory_digest" => nil,
      "status" => "prepared",
      "attempt_count" => 0,
      "authorization_digest" => nil,
      "last_error_code" => nil,
      "prepared_at" => DateTime.to_iso8601(now),
      "completed_at" => nil
    }

    Map.put(plan, "inventory_digest", inventory_digest(plan))
  end

  defp inventory_digest(plan) do
    [
      ["format", plan["format"]],
      ["format_version", plan["format_version"]],
      ["environment", plan["environment"]],
      ["workspace_id", plan["workspace_id"]],
      ["project_ids", plan["project_ids"]],
      ["snapshot_row_ids", plan["snapshot_row_ids"]],
      ["entity_version_row_ids", plan["entity_version_row_ids"]],
      ["prefixes", plan["prefixes"]],
      ["objects", Enum.map(plan["objects"], &[&1["key"], &1["size"]])]
    ]
    |> Jason.encode_to_iodata!()
    |> sha256()
  end

  defp sha256(value), do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)

  defp positive_unique_integers?(values) when is_list(values) do
    values == Enum.uniq(values) and Enum.all?(values, &(is_integer(&1) and &1 > 0))
  end

  defp positive_unique_integers?(_values), do: false

  defp valid_plan_object?(%{"key" => key, "size" => size} = object) do
    Enum.sort(Map.keys(object)) == ["key", "size"] and is_binary(key) and is_integer(size) and size >= 0
  end

  defp valid_plan_object?(_object), do: false

  defp revalidate_database_scope(repo, plan) do
    with {:ok, project_ids, snapshot_rows, entity_version_rows} <-
           load_scope(repo, plan["workspace_id"], scope_validation_limit(plan)),
         true <- project_ids == plan["project_ids"],
         true <- Enum.map(snapshot_rows, & &1["id"]) == plan["snapshot_row_ids"],
         true <- Enum.map(entity_version_rows, & &1["id"]) == plan["entity_version_row_ids"] do
      :ok
    else
      false -> {:error, :snapshot_reset_database_scope_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revalidate_storage_scope(adapter, plan) do
    with {:ok, current} <- list_exact_inventory(adapter, plan["prefixes"], length(plan["objects"]) + 1) do
      ensure_current_inventory_subset(current, plan["objects"])
    end
  end

  defp ensure_current_inventory_subset(current, original) do
    original_by_key = Map.new(original, &{&1["key"], &1["size"]})

    if Enum.all?(current, fn object -> original_by_key[object["key"]] == object["size"] end),
      do: :ok,
      else: {:error, :snapshot_reset_storage_scope_changed}
  end

  defp delete_inventory(adapter, plan, checkpoint) do
    plan["remaining_storage_keys"]
    |> Enum.chunk_every(@delete_batch_size)
    |> Enum.reduce_while({:ok, plan}, &delete_inventory_batch(&1, &2, adapter, checkpoint))
  end

  defp delete_inventory_batch(batch, {:ok, current_plan}, adapter, checkpoint) do
    {deleted, failed} = Enum.split_with(batch, &(safe_delete(adapter, &1) == :ok))
    updated = Map.put(current_plan, "remaining_storage_keys", current_plan["remaining_storage_keys"] -- deleted)
    continue_after_delete_batch(failed, updated, checkpoint)
  end

  defp continue_after_delete_batch([], updated, checkpoint) do
    case checkpoint_plan(checkpoint, updated) do
      :ok ->
        {:cont, {:ok, updated}}

      {:error, _reason} ->
        {:halt, {:error, :snapshot_reset_checkpoint_failed, mark_failed(updated, "checkpoint_failed")}}
    end
  end

  defp continue_after_delete_batch([_failed_key | _rest], updated, checkpoint) do
    failed_plan = mark_failed(updated, "storage_delete_failed")

    case checkpoint_plan(checkpoint, failed_plan) do
      :ok ->
        {:halt, {:error, :snapshot_reset_storage_delete_failed, failed_plan}}

      {:error, _reason} ->
        {:halt, {:error, :snapshot_reset_checkpoint_failed, mark_failed(updated, "checkpoint_failed")}}
    end
  end

  defp verify_prefixes_empty(adapter, prefixes) do
    case list_exact_inventory(adapter, prefixes, 1) do
      {:ok, []} -> :ok
      {:ok, _objects} -> {:error, :snapshot_reset_final_inventory_not_empty}
      {:error, reason} -> {:error, reason}
    end
  end

  defp final_zero_state(repo, adapter, plan) do
    case verify_prefixes_empty(adapter, plan["prefixes"]) do
      :ok -> final_database_zero_state(repo, plan)
      {:error, :snapshot_reset_final_inventory_not_empty} -> :incomplete
      {:error, :snapshot_reset_inventory_limit_exceeded} -> :incomplete
      {:error, reason} -> {:error, reason}
    end
  end

  defp final_database_zero_state(repo, plan) do
    case verify_database_scope_empty(repo, plan) do
      :ok -> :complete
      {:error, :snapshot_reset_final_database_not_empty} -> :incomplete
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_snapshot_rows(repo, plan) do
    case repo.transaction(fn -> delete_snapshot_rows_transaction(repo, plan) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, {:snapshot_reset_database_failed, reason}}
    end
  end

  defp delete_snapshot_rows_transaction(repo, plan) do
    snapshot_row_ids = plan["snapshot_row_ids"]
    entity_version_row_ids = plan["entity_version_row_ids"]

    with :ok <- lock_reset_workspace(repo, plan["workspace_id"]),
         :ok <- revalidate_database_scope(repo, plan),
         :ok <- clear_legacy_restoration_locks(repo, plan["workspace_id"]),
         {:ok, %{rows: deleted_entity_versions}} <-
           repo.query(
             """
             DELETE FROM entity_versions ev
             USING projects p
             WHERE ev.project_id = p.id AND p.workspace_id = $1 AND ev.id = ANY($2::bigint[])
             RETURNING ev.id
             """,
             [plan["workspace_id"], entity_version_row_ids]
           ),
         true <-
           exact_deleted_ids?(deleted_entity_versions, entity_version_row_ids),
         {:ok, %{rows: deleted_snapshots}} <-
           repo.query(
             """
             DELETE FROM project_snapshots ps
             USING projects p
             WHERE ps.project_id = p.id AND p.workspace_id = $1 AND ps.id = ANY($2::bigint[])
             RETURNING ps.id
             """,
             [plan["workspace_id"], snapshot_row_ids]
           ),
         true <- exact_deleted_ids?(deleted_snapshots, snapshot_row_ids),
         :ok <- verify_database_scope_empty(repo, plan) do
      :ok
    else
      false -> repo.rollback(:snapshot_reset_database_scope_changed)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp exact_deleted_ids?(deleted_rows, expected_ids) do
    Enum.sort(Enum.map(deleted_rows, fn [id] -> id end)) == Enum.sort(expected_ids)
  end

  defp lock_reset_workspace(repo, workspace_id) do
    case repo.query("SELECT id FROM workspaces WHERE id = $1 FOR UPDATE", [workspace_id]) do
      {:ok, %{rows: [[^workspace_id]]}} -> :ok
      {:ok, _result} -> {:error, :snapshot_reset_workspace_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clear_legacy_restoration_locks(repo, workspace_id) do
    case repo.query(
           """
           SELECT EXISTS (
             SELECT 1 FROM information_schema.columns
             WHERE table_name = 'projects' AND column_name = 'restoration_snapshot_id'
           )
           """,
           []
         ) do
      {:ok, %{rows: [[false]]}} ->
        :ok

      {:ok, %{rows: [[true]]}} ->
        case repo.query(
               """
               UPDATE projects
               SET restoration_in_progress = FALSE,
                   restoration_started_by_id = NULL,
                   restoration_started_at = NULL,
                   restoration_token = NULL,
                   restoration_claimed_by_job_id = NULL,
                   restoration_snapshot_id = NULL
               WHERE workspace_id = $1 AND restoration_snapshot_id IS NOT NULL
               """,
               [workspace_id]
             ) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_database_response}
    end
  end

  defp verify_database_scope_empty(repo, plan) do
    case load_scope(repo, plan["workspace_id"], scope_validation_limit(plan)) do
      {:ok, _project_ids, [], []} ->
        :ok

      {:ok, _project_ids, _snapshot_rows, _entity_version_rows} ->
        {:error, :snapshot_reset_final_database_not_empty}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scope_validation_limit(plan) do
    [plan["project_ids"], plan["snapshot_row_ids"], plan["entity_version_row_ids"]]
    |> Enum.map(&length/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp fail_execution(plan, reason, checkpoint) do
    failed = mark_failed(plan, inspect(reason))
    _checkpoint_result = checkpoint_plan(checkpoint, failed)
    {:error, reason, failed}
  end

  defp checkpoint_plan(checkpoint, plan) do
    case checkpoint.(plan) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_checkpoint_response}
    end
  rescue
    _exception -> {:error, :checkpoint_failed}
  catch
    _kind, _reason -> {:error, :checkpoint_failed}
  end

  defp safe_delete(adapter, key) do
    case adapter.delete(key) do
      :ok -> :ok
      _error -> {:error, :storage_delete_failed}
    end
  rescue
    _exception -> {:error, :storage_delete_failed}
  catch
    _kind, _reason -> {:error, :storage_delete_failed}
  end

  defp mark_failed(plan, code) when is_map(plan) do
    plan
    |> Map.put("status", "failed")
    |> Map.put("last_error_code", code |> to_string() |> String.slice(0, 160))
  end

  defp emit_reset_stop(plan, environment) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reset, :stop],
      %{
        object_count: length(plan["objects"]),
        snapshot_row_count: length(plan["snapshot_row_ids"]),
        entity_version_row_count: length(plan["entity_version_row_ids"]),
        attempt_count: plan["attempt_count"]
      },
      %{
        status: :completed,
        environment: environment,
        workspace_id: plan["workspace_id"],
        inventory_digest: plan["inventory_digest"]
      }
    )
  end
end
