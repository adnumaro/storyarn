defmodule Storyarn.Projects.Imports.SourceBundle.YarnProjectSources do
  @moduledoc false

  @supported_project_versions MapSet.new([2, 3, 4])
  @max_patterns_per_list 100
  @max_pattern_bytes 1_024
  @max_project_bytes 1_000_000
  @max_wildcard_work 25_000_000
  @unsupported_glob_characters ["[", "]", "{", "}"]

  @type file :: %{
          required(:path) => String.t(),
          required(:extension) => String.t(),
          required(:content) => binary()
        }

  @type compiled_pattern :: tuple()

  @spec select([file()]) :: {:ok, [file()]} | {:error, atom()}
  def select(files) when is_list(files) do
    case Enum.filter(files, &(&1.extension == ".yarnproject")) do
      [] ->
        # Yarn Spinner treats a workspace without a .yarnproject as one
        # implicit project containing all Yarn scripts.
        {:ok, files}

      [project] ->
        select_project_sources(files, project)

      _multiple_projects ->
        # A .yarnproject represents an independently compiled program. Merging
        # several of them would silently change both source scope and semantics.
        {:error, :invalid_json_structure}
    end
  end

  defp select_project_sources(files, project) do
    with {:ok, config} <- decode_project(project.content),
         {:ok, source_patterns} <-
           compile_patterns(config["sourceFiles"], project.path, :required),
         {:ok, exclude_patterns} <-
           compile_patterns(Map.get(config, "excludeFiles", []), project.path, :optional),
         :ok <- validate_wildcard_work(config, files) do
      selected =
        Enum.filter(files, fn
          %{extension: ".yarn", path: path} ->
            matches_any?(source_patterns, path) and
              not matches_any?(exclude_patterns, path)

          _other ->
            true
        end)

      if Enum.any?(selected, &(&1.extension == ".yarn")),
        do: {:ok, selected},
        else: {:error, :archive_missing_yarn_files}
    end
  end

  defp decode_project(content) when byte_size(content) <= @max_project_bytes do
    with {:ok, project} when is_map(project) <- Jason.decode(content),
         {:ok, version} <- project_field(project, "projectFileVersion"),
         true <- MapSet.member?(@supported_project_versions, version),
         {:ok, source_files} <- project_field(project, "sourceFiles"),
         {:ok, exclude_files} <- project_field(project, "excludeFiles", []) do
      {:ok,
       %{
         "projectFileVersion" => version,
         "sourceFiles" => source_files,
         "excludeFiles" => exclude_files
       }}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      _invalid_structure -> {:error, :invalid_json_structure}
    end
  end

  defp decode_project(_content), do: {:error, :invalid_json_structure}

  defp project_field(project, expected, default \\ :missing) do
    matches =
      Enum.filter(project, fn {key, _value} ->
        is_binary(key) and String.downcase(key) == String.downcase(expected)
      end)

    case matches do
      [{_key, value}] -> {:ok, value}
      [] when default != :missing -> {:ok, default}
      _missing_or_ambiguous -> {:error, :invalid_json_structure}
    end
  end

  defp compile_patterns(nil, _project_path, :required), do: {:error, :invalid_json_structure}
  defp compile_patterns(nil, _project_path, :optional), do: {:error, :invalid_json_structure}

  defp compile_patterns(patterns, project_path, presence) when is_list(patterns) do
    cond do
      presence == :required and patterns == [] ->
        {:error, :archive_missing_yarn_files}

      length(patterns) > @max_patterns_per_list ->
        {:error, :invalid_json_structure}

      true ->
        project_directory = project_path |> String.split("/") |> Enum.drop(-1)

        patterns
        |> Enum.reduce_while(
          {:ok, []},
          &compile_project_pattern(&1, &2, project_directory)
        )
        |> case do
          {:ok, compiled} -> {:ok, Enum.reverse(compiled)}
          error -> error
        end
    end
  end

  defp compile_patterns(_patterns, _project_path, _presence), do: {:error, :invalid_json_structure}

  defp compile_project_pattern(pattern, {:ok, acc}, project_directory) do
    with {:ok, normalized} <- normalize_pattern(pattern, project_directory),
         {:ok, compiled} <- compile_pattern(normalized) do
      {:cont, {:ok, [compiled | acc]}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp normalize_pattern(pattern, project_directory)
       when is_binary(pattern) and byte_size(pattern) > 0 and byte_size(pattern) <= @max_pattern_bytes do
    cond do
      String.contains?(pattern, [<<0>>, "\\"]) ->
        {:error, :invalid_json_structure}

      String.starts_with?(pattern, "/") or Regex.match?(~r/^[A-Za-z]:/u, pattern) ->
        {:error, :invalid_json_structure}

      String.contains?(pattern, @unsupported_glob_characters) ->
        {:error, :invalid_json_structure}

      true ->
        normalized = String.normalize(pattern, :nfc)
        segments = String.split(normalized, "/")

        if Enum.any?(segments, &(&1 == "")),
          do: {:error, :invalid_json_structure},
          else: resolve_pattern_segments(segments, project_directory)
    end
  end

  defp normalize_pattern(_pattern, _project_directory), do: {:error, :invalid_json_structure}

  defp resolve_pattern_segments(segments, project_directory) do
    segments
    |> Enum.reduce_while({:ok, project_directory}, fn
      ".", acc ->
        {:cont, acc}

      "..", {:ok, []} ->
        {:halt, {:error, :invalid_json_structure}}

      "..", {:ok, resolved} ->
        {:cont, {:ok, Enum.drop(resolved, -1)}}

      segment, {:ok, resolved} ->
        {:cont, {:ok, resolved ++ [segment]}}
    end)
    |> case do
      {:ok, []} -> {:error, :invalid_json_structure}
      {:ok, resolved} -> {:ok, Enum.join(resolved, "/")}
      error -> error
    end
  end

  defp compile_pattern(pattern) do
    if String.contains?(pattern, ["*", "?"]) do
      pattern
      |> String.split("/")
      |> Enum.reduce_while({:ok, []}, &compile_path_segment/2)
      |> case do
        {:ok, compiled} -> {:ok, compiled |> Enum.reverse() |> List.to_tuple()}
        error -> error
      end
    else
      {:ok, {:exact_path, String.downcase(pattern)}}
    end
  end

  defp compile_path_segment("**", {:ok, acc}), do: {:cont, {:ok, [:globstar | acc]}}

  defp compile_path_segment(segment, {:ok, acc}) do
    if String.contains?(segment, "**"),
      do: {:halt, {:error, :invalid_json_structure}},
      else: {:cont, {:ok, [compile_segment(segment) | acc]}}
  end

  defp compile_segment(segment) do
    if String.contains?(segment, ["*", "?"]) do
      matcher =
        segment
        |> String.downcase()
        |> String.graphemes()
        |> Enum.map(fn
          "*" -> :star
          "?" -> :any
          literal -> {:literal, literal}
        end)
        |> List.to_tuple()

      # Yarn Spinner constructs its Microsoft glob matcher with
      # OrdinalIgnoreCase, so source selection must not depend on the host
      # filesystem's case-sensitivity.
      {:segment, matcher}
    else
      {:exact_segment, String.downcase(segment)}
    end
  end

  defp matches_any?(patterns, path) do
    normalized_path = path |> String.normalize(:nfc) |> String.downcase()

    Enum.any?(patterns, fn
      {:exact_path, exact} -> exact == normalized_path
      pattern -> matches?(pattern, normalized_path)
    end)
  end

  # The reachable-state matcher gives globstar zero-or-more-directory
  # semantics without regex backtracking over the full path.
  defp matches?(pattern, path) do
    path_segments = String.split(path, "/", trim: true)
    final_state = tuple_size(pattern)

    states =
      [0]
      |> MapSet.new()
      |> epsilon_closure(pattern)
      |> consume_segments(path_segments, pattern)
      |> epsilon_closure(pattern)

    MapSet.member?(states, final_state)
  end

  defp consume_segments(states, [], _pattern), do: states

  defp consume_segments(states, [segment | rest], pattern) do
    next_states =
      Enum.reduce(
        states,
        MapSet.new(),
        &consume_path_state(&1, &2, pattern, segment)
      )

    next_states
    |> epsilon_closure(pattern)
    |> consume_segments(rest, pattern)
  end

  defp consume_path_state(state, acc, pattern, segment) do
    case pattern_token(pattern, state) do
      :globstar ->
        MapSet.put(acc, state)

      {:segment, matcher} ->
        maybe_advance_path_state(acc, state, segment_matches?(matcher, segment))

      {:exact_segment, ^segment} ->
        MapSet.put(acc, state + 1)

      {:exact_segment, _other} ->
        acc

      nil ->
        acc
    end
  end

  defp maybe_advance_path_state(acc, state, true), do: MapSet.put(acc, state + 1)
  defp maybe_advance_path_state(acc, _state, false), do: acc

  defp epsilon_closure(states, pattern) do
    expanded =
      Enum.reduce(states, states, fn state, acc ->
        if pattern_token(pattern, state) == :globstar,
          do: MapSet.put(acc, state + 1),
          else: acc
      end)

    if MapSet.equal?(expanded, states),
      do: states,
      else: epsilon_closure(expanded, pattern)
  end

  defp pattern_token(pattern, state) when state < tuple_size(pattern), do: elem(pattern, state)

  defp pattern_token(_pattern, _state), do: nil

  defp segment_matches?(matcher, segment) do
    final_state = tuple_size(matcher)

    states =
      [0]
      |> MapSet.new()
      |> segment_epsilon_closure(matcher)

    states =
      segment
      |> String.downcase()
      |> String.graphemes()
      |> Enum.reduce(
        states,
        &consume_segment_character(&1, &2, matcher)
      )
      |> segment_epsilon_closure(matcher)

    MapSet.member?(states, final_state)
  end

  defp consume_segment_character(character, current_states, matcher) do
    current_states
    |> Enum.reduce(
      MapSet.new(),
      &consume_character_state(&1, &2, matcher, character)
    )
    |> segment_epsilon_closure(matcher)
  end

  defp consume_character_state(state, acc, matcher, character) do
    case pattern_token(matcher, state) do
      :star -> MapSet.put(acc, state)
      :any -> MapSet.put(acc, state + 1)
      {:literal, ^character} -> MapSet.put(acc, state + 1)
      _no_match -> acc
    end
  end

  defp segment_epsilon_closure(states, matcher) do
    expanded =
      Enum.reduce(states, states, fn state, acc ->
        if pattern_token(matcher, state) == :star,
          do: MapSet.put(acc, state + 1),
          else: acc
      end)

    if MapSet.equal?(expanded, states),
      do: states,
      else: segment_epsilon_closure(expanded, matcher)
  end

  defp validate_wildcard_work(config, files) do
    wildcard_pattern_bytes =
      (config["sourceFiles"] ++ Map.get(config, "excludeFiles", []))
      |> Enum.filter(&String.contains?(&1, ["*", "?"]))
      |> Enum.sum_by(&byte_size/1)

    yarn_path_bytes =
      files
      |> Enum.filter(&(&1.extension == ".yarn"))
      |> Enum.sum_by(&(byte_size(&1.path) + 1))

    if wildcard_pattern_bytes * yarn_path_bytes <= @max_wildcard_work,
      do: :ok,
      else: {:error, :invalid_json_structure}
  end
end
