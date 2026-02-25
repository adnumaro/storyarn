# Oban Pro Reference

Patterns for Oban Pro workers, workflows, and batches.

## Worker Callback Difference

The most critical difference: **Oban Pro uses `process/1` not `perform/1`**.

```elixir
defmodule MyApp.Workers.ImportWorker do
  use Oban.Pro.Worker,
    queue: :imports,
    max_attempts: 5,
    unique: [period: 60, states: :incomplete]

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"import_id" => import_id}}) do
    :ok
  end
end
```

## Pro Worker Features

### Structured Jobs

Compile-time argument validation:

```elixir
use Oban.Pro.Worker,
  structured: [
    keys: [:user_id, :action, :metadata],
    required: [:user_id, :action]
  ]
```

### Recorded Jobs

Capture output for later retrieval:

```elixir
use Oban.Pro.Worker, recorded: true

@impl Oban.Pro.Worker
def process(%Oban.Job{} = job) do
  result = do_work(job.args)
  {:ok, result}  # result stored, retrievable via fetch_recorded/1
end

# Later:
{:ok, result} = Oban.Pro.Worker.fetch_recorded(job)
```

### Encrypted Jobs

AES-256-CTR encryption for args at rest:

```elixir
use Oban.Pro.Worker,
  encrypted: [key: {MyApp.Config, :oban_encryption_key, []}]
```

**Iron Law**: Encryption breaks uniqueness on `args` because encrypted args differ each time. Use `meta` for unique constraints:

```elixir
# ❌ Won't work — encrypted args differ each insertion
use Oban.Pro.Worker, encrypted: [...], unique: [keys: [:user_id]]

# ✅ Use meta for uniqueness with encryption
Oban.insert(
  MyWorker.new(%{sensitive: data}, meta: %{user_id: id}),
  unique: [keys: [], meta: [:user_id]]
)
```

## Unique Constraints (Enhanced)

Pro extends unique constraints:

```elixir
use Oban.Pro.Worker,
  unique: [
    period: :infinity,
    states: [:available, :scheduled, :executing],
    keys: [:user_id, :type],
    replace: [:scheduled_at]
  ]
```

## Workflows

Orchestrate dependent jobs with `Oban.Pro.Workers.Workflow`.

**Iron Law**: Workflow workers MUST use `Oban.Pro.Workers.Workflow`, NOT `Oban.Pro.Worker` or `Oban.Pro.Workflow`.

### Basic Workflow

```elixir
defmodule MyApp.Workers.ExtractWorker do
  use Oban.Pro.Workers.Workflow, queue: :pipelines

  @impl Oban.Pro.Workers.Workflow
  def process(%Oban.Job{args: %{"data_id" => id}}) do
    {:ok, extract(id)}
  end
end

# Build workflow with dependencies
Oban.Pro.Workers.Workflow.new_workflow()
|> Oban.Pro.Workers.Workflow.add(:extract, ExtractWorker.new(%{data_id: 1}))
|> Oban.Pro.Workers.Workflow.add(:transform, TransformWorker.new(%{}), deps: [:extract])
|> Oban.Pro.Workers.Workflow.add(:load, LoadWorker.new(%{}), deps: [:transform])
|> Oban.insert_all()
```

### Fan-Out Pattern

Multiple parallel jobs depending on one upstream:

```elixir
Oban.Pro.Workers.Workflow.new_workflow()
|> Oban.Pro.Workers.Workflow.add(:fetch, FetchWorker.new(%{url: url}))
|> Oban.Pro.Workers.Workflow.add(:resize_sm, ResizeWorker.new(%{size: "small"}), deps: [:fetch])
|> Oban.Pro.Workers.Workflow.add(:resize_md, ResizeWorker.new(%{size: "medium"}), deps: [:fetch])
|> Oban.Pro.Workers.Workflow.add(:resize_lg, ResizeWorker.new(%{size: "large"}), deps: [:fetch])
|> Oban.insert_all()
```

### Fan-In Pattern

One job depending on multiple parallel jobs:

```elixir
Oban.Pro.Workers.Workflow.new_workflow()
|> Oban.Pro.Workers.Workflow.add(:step_a, StepA.new(%{}))
|> Oban.Pro.Workers.Workflow.add(:step_b, StepB.new(%{}))
|> Oban.Pro.Workers.Workflow.add(:step_c, StepC.new(%{}))
|> Oban.Pro.Workers.Workflow.add(:merge, MergeWorker.new(%{}), deps: [:step_a, :step_b, :step_c])
|> Oban.insert_all()
```

### Appending to Running Workflows

Add jobs to an already-running workflow:

```elixir
Oban.Pro.Workers.Workflow.append_workflow(existing_workflow_id, fn workflow ->
  workflow
  |> Oban.Pro.Workers.Workflow.add(:extra, ExtraWorker.new(%{}), deps: [:transform])
end)
```

### Workflow Options

| Option | Default | Description |
|--------|---------|-------------|
| `ignore_cancelled` | `false` | Continue workflow even if deps are cancelled |
| `ignore_discarded` | `false` | Continue workflow even if deps are discarded |
| `waiting_delay` | `1_000` | ms between checking if deps are done |
| `waiting_limit` | `10` | Max checks before giving up |

## Batches

Process groups of jobs with callbacks when the batch completes.

```elixir
defmodule MyApp.Workers.EmailBatchWorker do
  use Oban.Pro.Workers.Batch, queue: :mailers

  @impl Oban.Pro.Workers.Batch
  def process(%Oban.Job{args: %{"email" => email}}) do
    Mailer.send(email)
  end

  @impl Oban.Pro.Workers.Batch
  def handle_completed(%Oban.Job{} = job) do
    # All jobs in batch completed successfully
    notify_admin("Batch done: #{job.args["batch_id"]}")
    :ok
  end

  @impl Oban.Pro.Workers.Batch
  def handle_exhausted(%Oban.Job{} = job) do
    # Some jobs failed after all retries
    :ok
  end
end
```

### Creating a Batch

```elixir
emails
|> Enum.map(&EmailBatchWorker.new(%{email: &1, batch_id: batch_id}))
|> Oban.insert_all()
```

### Batch Callbacks

| Callback | When |
|----------|------|
| `handle_attempted` | All jobs attempted (success or failure) |
| `handle_completed` | All jobs completed successfully |
| `handle_discarded` | Any job discarded (max attempts reached) |
| `handle_exhausted` | All jobs attempted AND some failed |

### Plugin Requirement

Batches require the BatchManager plugin in your Oban config:

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Pro.Plugins.BatchManager, []}
  ]
```

## Testing Pro Workers

```elixir
use Oban.Pro.Testing, repo: MyApp.Repo

test "processes import" do
  :ok = perform_job(ImportWorker, %{import_id: 123})
  assert ...
end
```
