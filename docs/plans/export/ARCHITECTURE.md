# Phase 8: Export — Architecture

> **Parent document:** [PHASE_8_EXPORT.md](../PHASE_8_EXPORT.md)

## Serializer Behaviour (Plugin Pattern)

All export formats implement a common behaviour. Engine formats are **plugin-style** — each module self-registers, so adding a new engine never touches the core export logic.

```elixir
defmodule Storyarn.Exports.Serializer do
  @doc """
  Serialize project data to the target format. Receives streamed data from
  DataCollector and writes output to a file path. Returns :ok or error.
  """
  @callback serialize_to_file(
              data :: DataCollector.stream_data(),
              file_path :: Path.t(),
              options :: ExportOptions.t(),
              callbacks :: keyword()
            ) :: :ok | {:error, term()}

  @doc """
  Serialize to in-memory binary. Used for small projects (sync export) and tests.
  """
  @callback serialize(project_data :: map(), options :: ExportOptions.t()) ::
              {:ok, output()} | {:error, term()}

  @doc "MIME content type for the exported file"
  @callback content_type() :: String.t()

  @doc "File extension (without dot)"
  @callback file_extension() :: String.t()

  @doc "Human-readable format name for UI"
  @callback format_label() :: String.t()

  @doc "Which content sections this format supports"
  @callback supported_sections() :: [:sheets | :flows | :scenes | :screenplays | :localization | :assets]

  @type output :: binary() | [{filename :: String.t(), content :: binary()}]
end
```

**Two modes:** `serialize/2` for tests and small sync exports, `serialize_to_file/4` for production streaming. The 4th arg is a keyword list with optional `progress_fn` callback. Serializers write JSON/XML/CSV incrementally to a temp file, never accumulating the full output in memory.

## Serializer Registry

```elixir
defmodule Storyarn.Exports.SerializerRegistry do
  @serializers %{
    storyarn:       Storyarn.Exports.Serializers.StoryarnJSON,
    ink:            Storyarn.Exports.Serializers.Ink,
    yarn:           Storyarn.Exports.Serializers.Yarn,
    unity:          Storyarn.Exports.Serializers.UnityJSON,
    godot:          Storyarn.Exports.Serializers.GodotJSON,
    godot_dialogic: Storyarn.Exports.Serializers.GodotDialogic,
    unreal:         Storyarn.Exports.Serializers.UnrealCSV,
    articy:         Storyarn.Exports.Serializers.ArticyXML
  }

  def get(format), do: Map.fetch(@serializers, format)
  def list, do: @serializers
  def formats, do: Map.keys(@serializers)
end
```

**Adding a new engine:** Create a module implementing the `Serializer` behaviour, add one line to the registry. No other file changes needed.

## Data Collection Layer (Streaming)

The collector uses **`Repo.stream`** to read from the database in batched chunks instead of loading the entire project into memory. This means a 50k-node project uses the same ~20MB of memory as a 500-node project.

```elixir
defmodule Storyarn.Exports.DataCollector do
  @doc """
  Stream project data for export. Each section is a lazy Stream that reads
  from Postgres in batches of 500 rows. Serializers consume chunks and write
  to file incrementally — nothing accumulates in memory.
  """
  def stream(project_id, %ExportOptions{} = opts) do
    %{
      project: load_project(project_id),
      sheets: maybe_stream(:sheets, project_id, opts),
      flows: maybe_stream(:flows, project_id, opts),
      scenes: maybe_stream(:scenes, project_id, opts),
      screenplays: maybe_stream(:screenplays, project_id, opts),
      localization: maybe_stream(:localization, project_id, opts),
      assets: maybe_stream(:assets, project_id, opts)
    }
  end

  defp maybe_stream(:flows, project_id, opts) do
    query = from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      preload: [:nodes, :connections],
      order_by: [asc: f.position]
    )
    query = maybe_filter_ids(query, opts.flow_ids)
    fn -> Repo.stream(query, max_rows: 500) end
  end

  @doc """
  For small projects or operations that need random access (validation,
  conflict detection), load everything into memory. The caller decides.
  """
  def collect(project_id, %ExportOptions{} = opts) do
    %{
      project: load_project(project_id),
      sheets: maybe_load(:sheets, project_id, opts),
      flows: maybe_load(:flows, project_id, opts),
      scenes: maybe_load(:scenes, project_id, opts),
      screenplays: maybe_load(:screenplays, project_id, opts),
      localization: maybe_load(:localization, project_id, opts),
      assets: maybe_load(:assets, project_id, opts)
    }
  end
end
```

**Dual API:** `stream/2` for exports (constant memory), `collect/2` for validation and conflict detection (needs random access). The serializer behaviour supports both — see Serializer Behaviour above.

**Why this matters:** A project with 50k flow nodes, 10k sheets, and 20 languages would be ~200MB in memory. With streaming, the process stays at ~20MB regardless of project size. The BEAM scheduler preempts the process every ~4000 reductions, so even a 30-second export doesn't block other LiveView sessions.

## Expression Transpiler (Critical Complexity)

This is the **hardest piece** of the entire export system. Storyarn conditions and instructions are stored as **structured data** (not free-text), but each game engine expects expressions in its own scripting language.

**Storyarn's two input modes:**
1. **Builder mode (primary):** Structured JSON — `{logic, rules: [{sheet, variable, operator, value}]}` for conditions, `{assignments: [{sheet, variable, operator, value}]}` for instructions. This is how 90%+ of conditions/instructions are authored.
2. **Code mode (secondary):** Free-text expressions like `{mc.jaime.health} > 50`. Used by advanced users. Requires parsing into an intermediate representation before transpilation.

```elixir
defmodule Storyarn.Exports.ExpressionTranspiler do
  @doc "Transpile a structured Storyarn condition to target engine syntax"
  @callback transpile_condition(condition :: map(), context :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Transpile structured Storyarn instruction assignments to target engine syntax"
  @callback transpile_instruction(assignments :: [map()], context :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Transpile a free-text code-mode expression (fallback path)"
  @callback transpile_code_expression(expression :: String.t(), context :: map()) ::
              {:ok, String.t()} | {:error, term()}
end
```

### Transpilation targets — Structured conditions (builder mode)

| Storyarn Structured Rule                                                         | Ink                           | Yarn                           | Unity (Lua)                               | Godot (GDScript)              | Unreal (Blueprint)            | articy:draft                  |
|----------------------------------------------------------------------------------|-------------------------------|--------------------------------|-------------------------------------------|-------------------------------|-------------------------------|-------------------------------|
| `{sheet: "mc.jaime", variable: "health", operator: "greater_than", value: "50"}` | `mc_jaime_health > 50`        | `$mc_jaime_health > 50`        | `Variable["mc.jaime.health"] > 50`        | `mc_jaime_health > 50`        | `mc.jaime.health > 50`        | `mc.jaime.health > 50`        |
| `{sheet: "mc.jaime", variable: "class", operator: "equals", value: "warrior"}`   | `mc_jaime_class == "warrior"` | `$mc_jaime_class == "warrior"` | `Variable["mc.jaime.class"] == "warrior"` | `mc_jaime_class == "warrior"` | `mc.jaime.class == "warrior"` | `mc.jaime.class == "warrior"` |
| `{logic: "all", rules: [rule1, rule2]}`                                          | `cond1 and cond2`             | `cond1 and cond2`              | `(cond1) and (cond2)`                     | `cond1 and cond2`             | `cond1 AND cond2`             | `cond1 && cond2`              |
| `{logic: "any", rules: [rule1, rule2]}`                                          | `cond1 or cond2`              | `cond1 or cond2`               | `(cond1) or (cond2)`                      | `cond1 or cond2`              | `cond1 OR cond2`              | `cond1 \|\| cond2`            |

> **Block-format conditions:** The transpiler must handle BOTH flat format (`{logic, rules}`) AND block format (`{logic, blocks}`) — see [STORYARN_JSON_FORMAT.md](./STORYARN_JSON_FORMAT.md#condition-formats). Block format introduces `type: "block"` and `type: "group"` nesting (max 1 level).

### Transpilation targets — Structured assignments (instruction mode)

| Storyarn Assignment                        | Ink           | Yarn                    | Unity (Lua)                          | Godot (GDScript)   | Unreal     | articy:draft  |
|--------------------------------------------|---------------|-------------------------|--------------------------------------|--------------------|------------|---------------|
| `{..., operator: "subtract", value: "10"}` | `~ x -= 10`   | `<<set $x to $x - 10>>` | `Variable["x"] = Variable["x"] - 10` | `x -= 10`          | `x -= 10`  | `x -= 10`     |
| `{..., operator: "set_true"}`              | `~ x = true`  | `<<set $x to true>>`    | `Variable["x"] = true`               | `x = true`         | `x = true` | `x = true`    |
| `{..., operator: "toggle"}`                | `~ x = not x` | `<<set $x to !$x>>`     | `Variable["x"] = not Variable["x"]`  | `x = !x`           | `x = !x`   | `x = !x`      |

> **NO `multiply` operator.** Storyarn's real operators are: `set`, `add`, `subtract`, `set_if_unset`, `set_true`, `set_false`, `toggle`, `clear`. See [PHASE_B_EXPRESSION_TRANSPILER.md](./PHASE_B_EXPRESSION_TRANSPILER.md#task-10-structured-assignment-transpiler) for complete mapping.
>
> **Variable-to-variable assignments:** When `value_type == "variable_ref"`, the value is another variable reference (not a literal). All emitters must handle this — e.g., Lua: `Variable["x"] = Variable["y"]`, Ink: `~ x = y`.

### Implementation approach

1. **Structured fast-path (primary):** Direct map traversal — iterate `rules[]` / `assignments[]`, lookup operator mapping per engine, emit target string. No parsing needed.
2. **Code-mode fallback:** Parse free-text expression into AST → transform per engine → emit target string. Only needed when user authored in code mode.

```elixir
defmodule Storyarn.Exports.ExpressionTranspiler.Unity do
  @behaviour Storyarn.Exports.ExpressionTranspiler

  # Structured condition — direct traversal, no parsing
  def transpile_condition(%{"logic" => logic, "rules" => rules}, ctx) do
    parts = Enum.map(rules, &transpile_rule/1)
    joiner = if logic == "all", do: " and ", else: " or "
    {:ok, Enum.join(parts, joiner)}
  end

  defp transpile_rule(%{"sheet" => sheet, "variable" => var, "operator" => op, "value" => val}) do
    var_ref = ~s(Variable["#{sheet}.#{var}"])
    "#{var_ref} #{lua_op(op)} #{lua_literal(val)}"
  end

  # Structured assignments — direct traversal
  def transpile_instruction(assignments, _ctx) when is_list(assignments) do
    lines = Enum.map(assignments, &transpile_assignment/1)
    {:ok, Enum.join(lines, "\n")}
  end

  defp transpile_assignment(%{"sheet" => sheet, "variable" => var, "operator" => "set", "value" => val}) do
    ~s(Variable["#{sheet}.#{var}"] = #{lua_literal(val)})
  end

  defp transpile_assignment(%{"sheet" => sheet, "variable" => var, "operator" => "subtract", "value" => val}) do
    ref = ~s(Variable["#{sheet}.#{var}"])
    "#{ref} = #{ref} - #{val}"
  end

  # Code-mode fallback — requires parsing
  def transpile_code_expression(expr, ctx) do
    with {:ok, ast} <- Parser.parse(expr) do
      {:ok, emit_lua(ast, ctx)}
    end
  end
end

# Parser only needed for code-mode expressions
defmodule Storyarn.Exports.ExpressionTranspiler.Parser do
  @doc "Parse free-text Storyarn expression into AST"
  def parse(expression) do
    # "{mc.jaime.health} > 50" →
    # {:comparison, {:var_ref, "mc.jaime.health"}, :gt, {:literal, 50}}
  end
end
```

**Key insight:** Since the builder stores structured data, the transpiler for builder-mode conditions/instructions is just a lookup table + string concatenation — no parser, no AST, no ambiguity. The parser is only needed for the code-mode fallback path, which is used by <10% of conditions.

---

## Key Architectural Decisions

### Why Behaviour + Registry over Protocol

Elixir protocols dispatch on data type, but all serializers receive the same `%ProjectData{}` map. We need dispatch on **format atom**, not on data shape. A behaviour + registry map gives us explicit registration, easy listing for UI, and zero magic.

### Why a shared Data Collector

Without it, each serializer would independently query the database with slightly different preloads, causing N+1 issues and inconsistencies. The collector does one aggressive load, and serializers are pure transformations on in-memory data. This also makes testing trivial — pass a fixture map, assert output.

### Why Expression Transpiler is separate from Serializers

Expressions cut across all engine formats. Embedding Lua generation inside the Unity serializer and GDScript generation inside the Godot serializer would duplicate parsing logic. The transpiler is its own module tree with the parser shared and emitters per-engine.

### Why round-trip before engine formats

If native JSON export → import isn't lossless, every engine format built on top of it inherits data loss bugs. The round-trip test is the foundation — it must pass before anything else matters.

### Why BEAM over Rust/sidecar for background processing

Export is I/O bound (Postgres reads + file writes), not CPU bound. The BEAM VM provides:
- **Preemptive scheduling** — a 30-second export yields to other processes every ~1ms automatically, no manual async/await or thread pools needed
- **Process isolation** — an export crash doesn't affect LiveView sessions; the supervisor restarts it
- **Cancellation** — `Oban.cancel_job/1` kills the process cleanly; no dangling threads or zombie NIFs
- **Progress reporting** — PubSub broadcasts from within the export process to the LiveView in real-time, zero coordination overhead

A Rust NIF would block the BEAM scheduler (requiring dirty scheduler hacks), force data serialization/deserialization across the FFI boundary, and make debugging 10x harder. The ~3 seconds saved on JSON encoding doesn't justify the complexity.

### Why streaming from DB (not load-all-then-serialize)

A 50k-node project with all relations is ~200MB in memory. Streaming via `Repo.stream` with 500-row batches keeps memory at ~20MB constant. This is the difference between "works for any project size" and "OOMs on large projects." The serializers write to file incrementally, so the full output never exists in memory either.

### Why dual sync/async mode

Small projects (<1000 entities) return instantly via sync export — no Oban job, no progress bar, just a download. This covers the 95% case. Oban is reserved for large projects where the user needs progress feedback and the export takes >2 seconds. The threshold is configurable.

### Why sync-first in implementation order

Build all serialization logic as pure functions first (sync mode). They're easy to test — pass a map, assert output. Then wrap with Oban for async. This means the core logic is proven before adding job infrastructure, progress tracking, and crash recovery.
