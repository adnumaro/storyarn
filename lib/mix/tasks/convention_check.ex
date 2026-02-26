defmodule Mix.Tasks.Convention.Check do
  @moduledoc """
  Checks Storyarn convention compliance across the project.

  Runs the same rules as the PostToolUse hook but scans all Elixir files.

  ## Usage

      mix convention.check                    # Check all files
      mix convention.check --fix-suggestions  # Show fix suggestions
      mix convention.check lib/storyarn_web/  # Check specific directory

  ## Rules

  | Rule                     | Scope     | Description                                    |
  |--------------------------|-----------|------------------------------------------------|
  | raw_without_sanitizer    | web only  | raw() must use HtmlSanitizer.sanitize_html/1   |
  | datetime_utc_now         | all       | Use TimeHelpers.now/0 instead                  |
  | facade_bypass            | web only  | Call context facade, not submodules             |
  | string_to_atom           | all       | Prefer to_existing_atom with allowlist          |
  | sql_interpolation        | all       | No string interpolation in Ecto queries         |
  | put_flash_without_gettext| web only  | put_flash must use gettext/dgettext             |
  | native_dialog            | all       | No window.confirm/alert/prompt or data-confirm  |
  | inline_slugify           | all       | Use NameNormalizer, not private slugify          |

  ## Suppression

  Suppress inline with comments:

      # storyarn:disable                    — disable all rules for this line
      # storyarn:disable:datetime_utc_now   — disable specific rule
      # storyarn:disable-start              — disable block start
      # storyarn:disable-end                — disable block end
  """

  use Mix.Task

  @shortdoc "Check Storyarn convention compliance"

  @rules [
    :raw_without_sanitizer,
    :datetime_utc_now,
    :facade_bypass,
    :string_to_atom,
    :sql_interpolation,
    :put_flash_without_gettext,
    :native_dialog,
    :inline_slugify
  ]

  @facade_submodules ~w(
    SheetCrud SheetQueries BlockCrud TableCrud
    FlowCrud NodeCreate NodeUpdate NodeDelete ConnectionCrud
    SceneCrud LayerCrud ZoneCrud PinCrud AnnotationCrud
    ScreenplayCrud ElementCrud ScreenplayQueries
    LanguageCrud TextCrud GlossaryCrud BatchTranslator
    ProjectCrud WorkspaceCrud
  )

  @impl Mix.Task
  def run(args) do
    {opts, paths} = parse_args(args)

    files =
      paths
      |> list_elixir_files()
      |> Enum.reject(&String.contains?(&1, "_build/"))
      |> Enum.reject(&String.contains?(&1, "deps/"))
      |> Enum.reject(&String.contains?(&1, "convention_check.ex"))

    violations =
      files
      |> Enum.flat_map(&check_file/1)
      |> Enum.sort_by(fn {rule, _file, line, _msg} -> {rule, line} end)

    print_results(violations, opts)

    unless violations == [] do
      Mix.shell().error("Convention check failed with #{length(violations)} violation(s)")
    end
  end

  defp parse_args(args) do
    {opts, paths, _} =
      OptionParser.parse(args, switches: [fix_suggestions: :boolean])

    paths = if paths == [], do: ["lib/"], else: paths
    {opts, paths}
  end

  defp list_elixir_files(paths) do
    Enum.flat_map(paths, fn path ->
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*.{ex,exs}"))
      else
        if File.exists?(path), do: [path], else: []
      end
    end)
  end

  defp check_file(file_path) do
    content = File.read!(file_path)
    lines = String.split(content, "\n")
    is_web = String.contains?(file_path, "storyarn_web")
    suppressed = build_suppression_map(lines)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      if Map.get(suppressed, line_num, false) == :all do
        []
      else
        rules_for_line(line, line_num, file_path, is_web)
        |> Enum.reject(fn {rule, _, _, _} ->
          rule_suppressed?(suppressed, line_num, rule)
        end)
      end
    end)
  end

  defp build_suppression_map(lines) do
    {map, _in_block} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, false}, fn {line, num}, {map, in_block} ->
        cond do
          String.contains?(line, "storyarn:disable-start") ->
            {map, true}

          String.contains?(line, "storyarn:disable-end") ->
            {map, false}

          in_block ->
            {Map.put(map, num, :all), true}

          String.match?(line, ~r/storyarn:disable($|[^-])/) ->
            # Disable all rules for this line AND next line
            {map |> Map.put(num, :all) |> Map.put(num + 1, :all), false}

          String.match?(line, ~r/storyarn:disable:(\w+)/) ->
            [_, rule] = Regex.run(~r/storyarn:disable:(\w+)/, line)
            rule_atom = String.to_atom(rule)
            # Suppress on this line and next line
            existing = Map.get(map, num, [])
            existing_next = Map.get(map, num + 1, [])

            new_map =
              map
              |> Map.put(num, if(is_list(existing), do: [rule_atom | existing], else: existing))
              |> Map.put(
                num + 1,
                if(is_list(existing_next),
                  do: [rule_atom | existing_next],
                  else: existing_next
                )
              )

            {new_map, false}

          true ->
            {map, in_block}
        end
      end)

    map
  end

  defp rule_suppressed?(suppressed, line_num, rule) do
    case Map.get(suppressed, line_num) do
      :all -> true
      rules when is_list(rules) -> rule in rules
      _ -> false
    end
  end

  defp rules_for_line(line, line_num, file, is_web) do
    # Skip comments
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "#") or String.starts_with?(trimmed, "//") do
      []
    else
      checks = [
        &check_datetime_utc_now/4,
        &check_string_to_atom/4,
        &check_sql_interpolation/4,
        &check_native_dialog/4,
        &check_inline_slugify/4
      ]

      web_checks = [
        &check_raw_without_sanitizer/4,
        &check_facade_bypass/4,
        &check_put_flash_without_gettext/4
      ]

      all_checks = if is_web, do: checks ++ web_checks, else: checks

      Enum.flat_map(all_checks, fn check -> check.(line, line_num, file, trimmed) end)
    end
  end

  # === RULES ===

  defp check_raw_without_sanitizer(line, line_num, file, _trimmed) do
    if String.match?(line, ~r/\braw\(/) and
         not String.contains?(line, "sanitize_html") and
         not String.contains?(line, "sanitize_and_interpolate") do
      [
        {:raw_without_sanitizer, file, line_num,
         "raw() without HtmlSanitizer.sanitize_html/1 — XSS risk"}
      ]
    else
      []
    end
  end

  defp check_datetime_utc_now(line, line_num, file, _trimmed) do
    if String.contains?(line, "DateTime.utc_now") and
         not String.contains?(line, "TimeHelpers") and
         not String.contains?(line, "time_helpers") and
         not String.contains?(file, "time_helpers.ex") and
         not String.match?(line, ~r/DateTime\.(diff|compare|after\?|before\?)/) and
         not String.match?(line, ~r/\^DateTime\.utc_now/) do
      [{:datetime_utc_now, file, line_num, "Use TimeHelpers.now/0 instead of DateTime.utc_now()"}]
    else
      []
    end
  end

  defp check_facade_bypass(line, line_num, file, _trimmed) do
    if Enum.any?(@facade_submodules, &String.contains?(line, &1 <> ".")) and
         not String.contains?(file, "name_normalizer") do
      [{:facade_bypass, file, line_num, "Call through context facade, not submodule directly"}]
    else
      []
    end
  end

  defp check_string_to_atom(line, line_num, file, _trimmed) do
    if String.match?(line, ~r/String\.to_atom\b/) do
      [
        {:string_to_atom, file, line_num,
         "String.to_atom/1 — prefer String.to_existing_atom/1 with allowlist guard"}
      ]
    else
      []
    end
  end

  defp check_sql_interpolation(line, line_num, file, _trimmed) do
    # Only match Ecto-style from: `from(x in ...` or `from x in ...` with interpolation
    # Exclude string literals containing the word "from" (e.g., "No connection from #{id}")
    if String.match?(line, ~r/\bfrom\s*[\(]?\s*\w+\s+in\b.*#\{/) or
         String.match?(line, ~r/Repo\.(query|query!)\s*[\(]?.*#\{/) do
      [
        {:sql_interpolation, file, line_num,
         "String interpolation in Ecto query — SQL injection risk. Use ^pinning."}
      ]
    else
      []
    end
  end

  defp check_put_flash_without_gettext(line, line_num, file, _trimmed) do
    if String.match?(line, ~r/put_flash\(.*,\s*"[A-Za-z]/) and
         not String.match?(line, ~r/gettext|dgettext|ngettext/) do
      [
        {:put_flash_without_gettext, file, line_num,
         "put_flash with hardcoded string — use gettext/dgettext"}
      ]
    else
      []
    end
  end

  defp check_native_dialog(line, line_num, file, _trimmed) do
    if String.match?(line, ~r/window\.(confirm|alert|prompt)\b|data-confirm/) do
      [{:native_dialog, file, line_num, "No browser-native dialogs — use <.confirm_modal>"}]
    else
      []
    end
  end

  defp check_inline_slugify(line, line_num, file, _trimmed) do
    # Only flag private slugify/variablify definitions that are reimplementations.
    # Exclude generate_slug wrappers that delegate to NameNormalizer (legitimate pattern).
    if String.match?(line, ~r/defp\s+(slugify|variablify|normalize_name)\b/) and
         not String.contains?(file, "name_normalizer") do
      [
        {:inline_slugify, file, line_num,
         "Use NameNormalizer.slugify/1 or variablify/1 instead of private function"}
      ]
    else
      []
    end
  end

  # === OUTPUT ===

  defp print_results([], _opts) do
    Mix.shell().info("#{IO.ANSI.green()}✓ No convention violations found.#{IO.ANSI.reset()}")
  end

  defp print_results(violations, opts) do
    grouped = Enum.group_by(violations, fn {rule, _, _, _} -> rule end)

    Mix.shell().info("")

    Mix.shell().info(
      "#{IO.ANSI.red()}Convention violations: #{length(violations)}#{IO.ANSI.reset()}"
    )

    Mix.shell().info("")

    for rule <- @rules, Map.has_key?(grouped, rule) do
      rule_violations = grouped[rule]
      count = length(rule_violations)

      Mix.shell().info(
        "#{IO.ANSI.yellow()}[#{rule}]#{IO.ANSI.reset()} — #{count} violation#{if count > 1, do: "s", else: ""}"
      )

      for {_rule, file, line_num, msg} <- rule_violations do
        Mix.shell().info("  #{file}:#{line_num} — #{msg}")
      end

      if opts[:fix_suggestions] do
        Mix.shell().info("  #{IO.ANSI.cyan()}Fix: #{fix_suggestion(rule)}#{IO.ANSI.reset()}")
      end

      Mix.shell().info("")
    end

    Mix.shell().info("Suppress with: # storyarn:disable:rule_name")
  end

  defp fix_suggestion(:raw_without_sanitizer),
    do: "Wrap with HtmlSanitizer.sanitize_html/1 before passing to raw()"

  defp fix_suggestion(:datetime_utc_now),
    do: "alias Storyarn.Shared.TimeHelpers, then use TimeHelpers.now()"

  defp fix_suggestion(:facade_bypass),
    do: "Use the context facade (e.g., Sheets.function() not Sheets.SheetCrud.function())"

  defp fix_suggestion(:string_to_atom),
    do: "Use String.to_existing_atom/1 with a `when field in ~w(...)` allowlist guard"

  defp fix_suggestion(:sql_interpolation),
    do: "Use ^variable pinning in Ecto queries instead of \#{interpolation}"

  defp fix_suggestion(:put_flash_without_gettext),
    do: "Use gettext(\"msg\") or dgettext(\"domain\", \"msg\")"

  defp fix_suggestion(:native_dialog),
    do: "Use <.confirm_modal> component instead"

  defp fix_suggestion(:inline_slugify),
    do: "Use NameNormalizer.slugify/1, variablify/1, or shortcutify/1"
end
