# Phase 8E: Scale & API

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)
>
> **Tasks:** 22-25 of 25
>
> **Dependencies:** Phase D (Tasks 18-19)

**Goal:** Add background processing with Oban for large projects, crash recovery, cleanup, and REST API endpoints.

---

## Tasks

| Order | Task                                    | Dependencies | Testable Outcome                             |
|-------|-----------------------------------------|--------------|----------------------------------------------|
| 22    | Oban ExportWorker + queue config        | Tasks 18-19  | Background export with progress broadcast    |
| 23    | Sync/async threshold decision logic     | Task 22      | Small projects sync, large projects async    |
| 24    | Cleanup cron + retry with checkpoint    | Task 22      | Old exports purged, crash recovery works     |
| 25    | REST API endpoints                      | Tasks 1-24   | Programmatic export/import access            |

---

## Task 22: Oban ExportWorker + Queue Config

### Oban Configuration

```elixir
# config/config.exs
config :storyarn, Oban,
  repo: Storyarn.Repo,
  queues: [
    default: 10,          # Normal jobs (emails, notifications)
    exports: 3,           # Max 3 concurrent exports (controlled by RAM, not CPU)
    imports: 2,           # Max 2 concurrent imports (heavy DB writes)
    maintenance: 1        # Cleanup old export files
  ]
```

**Why limit to 3 exports?** Not because BEAM can't handle more — it can handle thousands. The limit is practical: each export holds a Postgres transaction open (for `Repo.stream` consistency) and writes to disk. 3 concurrent exports + normal app traffic is a safe default. Tunable per deployment.

### Export Worker

```elixir
defmodule Storyarn.Exports.ExportWorker do
  use Oban.Worker,
    queue: :exports,
    max_attempts: 2,
    priority: 1

  alias Storyarn.Exports.{DataCollector, SerializerRegistry, Validator}

  @impl Oban.Worker
  def perform(%Job{args: %{"project_id" => project_id, "format" => format,
                            "options" => options, "user_id" => user_id,
                            "export_job_id" => export_job_id}}) do
    opts = ExportOptions.from_map(options)
    serializer = SerializerRegistry.get!(String.to_existing_atom(format))

    # 1. Count entities for progress tracking
    total = count_entities(project_id, opts)
    update_job_status(export_job_id, :processing, %{total: total})

    # 2. Optional pre-validation
    if opts.validate_before_export do
      case Validator.validate_project(project_id, opts) do
        %{status: :errors} = result ->
          update_job_status(export_job_id, :failed, %{validation: result})
          {:error, :validation_failed}
        result ->
          update_job_status(export_job_id, :processing, %{validation: result})
          do_export(project_id, opts, serializer, export_job_id, user_id, total)
      end
    else
      do_export(project_id, opts, serializer, export_job_id, user_id, total)
    end
  end

  defp do_export(project_id, opts, serializer, export_job_id, user_id, total) do
    tmp_path = Briefly.create!(extname: ".#{serializer.file_extension()}")

    # 3. Stream from DB -> serialize to file (constant memory)
    Repo.transaction(fn ->
      data = DataCollector.stream(project_id, opts)

      serializer.serialize_to_file(data, tmp_path, opts,
        progress_fn: fn current ->
          if rem(current, 50) == 0 do
            percent = min(trunc(current / total * 100), 99)
            update_job_status(export_job_id, :processing, %{progress: percent})
            broadcast_progress(user_id, project_id, percent)
          end
        end
      )
    end)

    # 4. Upload result file to storage
    file_key = "exports/#{project_id}/#{export_job_id}.#{serializer.file_extension()}"
    file_size = File.stat!(tmp_path).size
    Assets.Storage.adapter().upload(file_key, File.read!(tmp_path), serializer.content_type())
    File.rm(tmp_path)

    # 5. Mark complete and notify user
    update_job_status(export_job_id, :completed, %{
      progress: 100,
      file_key: file_key,
      file_size: file_size
    })
    broadcast_complete(user_id, project_id, export_job_id)

    :ok
  end

  defp broadcast_progress(user_id, project_id, percent) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub,
      "user:#{user_id}:exports",
      {:export_progress, project_id, percent})
  end

  defp broadcast_complete(user_id, project_id, export_job_id) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub,
      "user:#{user_id}:exports",
      {:export_complete, project_id, export_job_id})
  end
end
```

### LiveView Integration (Real-Time Progress)

```elixir
defmodule StoryarnWeb.ExportLive.Index do
  use StoryarnWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub,
        "user:#{socket.assigns.current_scope.user.id}:exports")
    end
    {:ok, assign(socket, export_status: :idle, export_progress: 0)}
  end

  def handle_event("start_export", %{"format" => format} = params, socket) do
    {:ok, export_job} = Exports.create_export_job(socket.assigns.project, %{
      format: format,
      options: build_options(params),
      user_id: socket.assigns.current_scope.user.id
    })

    %{project_id: socket.assigns.project.id, format: format,
      options: build_options(params),
      user_id: socket.assigns.current_scope.user.id,
      export_job_id: export_job.id}
    |> Storyarn.Exports.ExportWorker.new()
    |> Oban.insert()

    {:noreply, assign(socket, export_status: :processing, export_progress: 0)}
  end

  def handle_info({:export_progress, _project_id, percent}, socket) do
    {:noreply, assign(socket, export_progress: percent)}
  end

  def handle_info({:export_complete, _project_id, export_job_id}, socket) do
    {:noreply, assign(socket,
      export_status: :complete,
      export_progress: 100,
      download_job_id: export_job_id)}
  end
end
```

## Task 23: Sync/Async Threshold

```elixir
defmodule Storyarn.Exports do
  @sync_threshold 1000  # entities

  def export_project(project, opts) do
    total = count_entities(project.id, opts)

    if total <= @sync_threshold do
      export_sync(project, opts)
    else
      export_async(project, opts)
    end
  end

  defp export_sync(project, opts) do
    data = DataCollector.collect(project.id, opts)
    serializer = SerializerRegistry.get!(opts.format)
    serializer.serialize(data, opts)
  end

  defp export_async(project, opts) do
    {:ok, job} = create_export_job(project, opts)
    %{project_id: project.id, format: opts.format,
      options: opts, export_job_id: job.id}
    |> ExportWorker.new()
    |> Oban.insert()
    {:async, job}
  end
end
```

## Task 24: Cleanup Cron + Retry with Checkpoint

### Automatic Cleanup

Old export files are deleted after 24 hours via a scheduled Oban cron job.

```elixir
# config/config.exs
config :storyarn, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 */6 * * *", Storyarn.Exports.CleanupWorker}  # Every 6 hours
    ]}
  ]

defmodule Storyarn.Exports.CleanupWorker do
  use Oban.Worker, queue: :maintenance

  @impl Oban.Worker
  def perform(_job) do
    Exports.cleanup_expired_exports(hours: 24)
    :ok
  end
end
```

### Retry with Checkpoint

If a node restarts mid-export (deploy, OOM), the job retries from checkpoint.

```elixir
def perform(%Job{attempt: attempt, args: args}) when attempt > 1 do
  case check_partial_export(args["export_job_id"]) do
    {:partial, last_entity_id, tmp_path} ->
      resume_export(args, last_entity_id, tmp_path)
    nil ->
      do_export(args)
  end
end
```

### Cancellation

```elixir
def handle_event("cancel_export", %{"job_id" => job_id}, socket) do
  case Oban.cancel_job(job_id) do
    :ok ->
      Exports.update_job_status(job_id, :cancelled)
      {:noreply, assign(socket, export_status: :idle)}
    _ ->
      {:noreply, socket}
  end
end
```

### Temp file cleanup

Use `Briefly` for temp paths — automatically cleaned on process exit. Also explicit `File.rm` on success, failure, and cancellation.

## Task 25: REST API Endpoints

### Export Endpoints

```elixir
# Start export job (async for large projects)
POST /api/projects/:id/exports
Body: { format: "storyarn", options: {...} }
Response: { job_id: "uuid", status: "processing" }

# Check export status
GET /api/projects/:id/exports/:job_id
Response: { status: "completed", download_url: "..." }

# Download export (direct)
GET /api/projects/:id/exports/:job_id/download
Response: File download

# Quick export (sync, small projects)
GET /api/projects/:id/export
Query: ?format=storyarn&include_assets=references
Response: JSON file download
```

### Import Endpoints

```elixir
# Upload for import
POST /api/projects/:id/imports
Body: multipart/form-data with file
Response: { import_id: "uuid", preview: {...} }

# Execute import
POST /api/projects/:id/imports/:import_id/execute
Body: { conflict_resolution: "overwrite" }
Response: { status: "completed", report: {...} }
```

---

## Performance Characteristics

| Project Size   | Entities | Memory    | Time (est.) | Mode  |
|----------------|----------|-----------|-------------|-------|
| Small          | <500     | ~5MB      | <2s         | Sync  |
| Medium         | 500-5k   | ~20MB     | 2-10s       | Async |
| Large          | 5k-50k   | ~20MB*    | 10-60s      | Async |
| Massive        | 50k+     | ~20MB*    | 1-5min      | Async |

*Streaming keeps memory constant regardless of project size. The bottleneck is Postgres query time, not serialization.

---

## Testing Strategy

- [ ] Concurrent export jobs (Oban)
- [ ] Sync threshold decision (small → sync, large → async)
- [ ] Progress broadcasting (PubSub)
- [ ] Cancellation via `Oban.cancel_job/1`
- [ ] Cleanup cron removes old files
- [ ] Retry with checkpoint recovery
- [ ] API endpoints return correct responses
