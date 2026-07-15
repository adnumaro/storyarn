defmodule Storyarn.Imports.Parsers.Yarn.Document do
  @moduledoc false

  alias Storyarn.Imports.ImportIssue

  @type line :: %{text: String.t(), line: pos_integer(), indent: non_neg_integer()}

  @type limits :: [
          max_documents: pos_integer(),
          max_statements_per_document: pos_integer(),
          max_total_statements: pos_integer(),
          max_total_source_lines: pos_integer(),
          max_line_bytes: pos_integer()
        ]

  @spec parse_files([map()], limits()) :: {:ok, [map()], [ImportIssue.t()]} | {:error, atom() | tuple()}
  def parse_files(files, limits) do
    with :ok <- preflight_limits(files, limits) do
      Enum.reduce_while(files, {:ok, [], []}, &parse_file_into/2)
    end
  end

  defp parse_file_into(file, {:ok, documents, issues}) do
    case parse_file(file) do
      {:ok, parsed, file_issues} ->
        {:cont, {:ok, documents ++ parsed, issues ++ file_issues}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  # Check source budgets over a lazy line stream before building the line maps
  # and nested AST. Physical lines are bounded independently, and every
  # substantive body line counts because options and conditional branches each
  # allocate parser/runtime data even when normalization later groups them.
  defp preflight_limits(files, limits) do
    initial = %{
      documents: 0,
      total_statements: 0,
      total_source_lines: 0,
      document_statements: 0,
      phase: :headers
    }

    files
    |> Enum.reduce_while({:ok, initial}, fn %{content: content}, {:ok, state} ->
      state = %{state | phase: :headers, document_statements: 0}

      case preflight_file(content, state, limits) do
        {:ok, next_state} -> {:cont, {:ok, next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _state} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp preflight_file(content, state, limits) do
    content
    |> String.splitter("\n", trim: false)
    |> Enum.reduce_while({:ok, state}, fn text, {:ok, acc} ->
      case preflight_line(text, acc, limits) do
        {:ok, next_acc} -> {:cont, {:ok, next_acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp preflight_line(text, state, limits) do
    total_source_lines = state.total_source_lines + 1

    cond do
      byte_size(text) > Keyword.fetch!(limits, :max_line_bytes) ->
        {:error, :yarn_statement_limit_exceeded}

      total_source_lines > Keyword.fetch!(limits, :max_total_source_lines) ->
        {:error, :yarn_statement_limit_exceeded}

      true ->
        do_preflight_line(text, %{state | total_source_lines: total_source_lines}, limits)
    end
  end

  defp do_preflight_line(text, %{phase: :headers} = state, limits) do
    if String.trim(text) == "---" do
      documents = state.documents + 1

      if documents > Keyword.fetch!(limits, :max_documents) do
        {:error, :yarn_document_limit_exceeded}
      else
        {:ok,
         %{
           state
           | documents: documents,
             document_statements: 0,
             phase: :body
         }}
      end
    else
      {:ok, state}
    end
  end

  defp do_preflight_line(text, %{phase: :body} = state, limits) do
    trimmed = String.trim(text)

    cond do
      trimmed == "===" ->
        {:ok, %{state | phase: :headers, document_statements: 0}}

      trimmed == "" or String.starts_with?(trimmed, "//") ->
        {:ok, state}

      true ->
        # Count every substantive source line conservatively. Each option and
        # conditional branch allocates its own AST/runtime data even when the
        # final normalized representation groups those lines together.
        consume_statement(state, limits)
    end
  end

  defp consume_statement(state, limits) do
    document_statements = state.document_statements + 1
    total_statements = state.total_statements + 1

    if document_statements > Keyword.fetch!(limits, :max_statements_per_document) or
         total_statements > Keyword.fetch!(limits, :max_total_statements) do
      {:error, :yarn_statement_limit_exceeded}
    else
      {:ok,
       %{
         state
         | document_statements: document_statements,
           total_statements: total_statements
       }}
    end
  end

  defp parse_file(%{alias: source, content: content}) do
    lines =
      content
      |> String.split("\n", trim: false)
      |> Enum.with_index(1)
      |> Enum.map(fn {text, line} -> %{text: text, line: line, indent: indentation(text)} end)

    parse_documents(lines, source, [], [])
  end

  defp parse_documents(lines, source, documents, issues) do
    lines = Enum.drop_while(lines, &ignorable_outside_node?/1)

    case lines do
      [] ->
        {:ok, Enum.reverse(documents), Enum.reverse(issues)}

      _other ->
        parse_next_document(lines, source, documents, issues)
    end
  end

  defp parse_headers(lines) do
    result = Enum.reduce_while(lines, {:ok, %{}}, &parse_header_line/2)
    finalize_headers(result, lines)
  end

  defp parse_next_document(lines, source, documents, issues) do
    with {:ok, headers, body_start, rest} <- parse_headers(lines),
         {:ok, body_lines, rest} <- take_body(rest),
         {:ok, body, [], body_issues} <- parse_sequence(body_lines, source, []),
         {:ok, document} <- build_document(headers, body, source, body_start) do
      document_issues = header_issues(headers, source) ++ body_issues

      parse_documents(
        rest,
        source,
        [document | documents],
        Enum.reverse(document_issues, issues)
      )
    end
  end

  defp header_issues(headers, source) do
    if Map.has_key?(headers, "when") do
      [ImportIssue.new(:error, :unsupported_yarn_node_condition, source: source)]
    else
      []
    end
  end

  defp build_document(%{"title" => title} = headers, body, source, body_start) when is_binary(title) do
    build_document_with_title(String.trim(title), headers, body, source, body_start)
  end

  defp build_document(_headers, _body, source, body_start), do: {:error, {:missing_yarn_title, source, body_start}}

  defp build_document_with_title("", _headers, _body, source, body_start),
    do: {:error, {:missing_yarn_title, source, body_start}}

  defp build_document_with_title(title, headers, body, source, body_start) do
    {:ok,
     %{
       title: title,
       headers: headers,
       body: body,
       source: source,
       line: body_start
     }}
  end

  defp parse_header_line(line, {:ok, headers}) do
    text = String.trim(line.text)

    cond do
      text == "---" -> {:halt, {:done, headers, line.line + 1}}
      text == "" or String.starts_with?(text, "//") -> {:cont, {:ok, headers}}
      true -> parse_header_value(text, line.line, headers)
    end
  end

  defp parse_header_value(text, line_number, headers) do
    case String.split(text, ":", parts: 2) do
      [key, value] -> {:cont, {:ok, Map.put(headers, String.trim(key), String.trim(value))}}
      _other -> {:halt, {:error, {:invalid_yarn_header, line_number}}}
    end
  end

  defp finalize_headers(result, lines) do
    case result do
      {:done, headers, body_start} ->
        delimiter_index = Enum.find_index(lines, &(String.trim(&1.text) == "---"))
        {:ok, headers, body_start, Enum.drop(lines, delimiter_index + 1)}

      {:error, reason} ->
        {:error, reason}

      {:ok, _headers} ->
        {:error, :missing_yarn_body_start}
    end
  end

  defp take_body(lines) do
    case Enum.split_while(lines, &(String.trim(&1.text) != "===")) do
      {_body, []} -> {:error, :missing_yarn_body_end}
      {body, [_delimiter | rest]} -> {:ok, body, rest}
    end
  end

  defp parse_sequence(lines, source, stop_commands) do
    do_parse_sequence(lines, source, stop_commands, [], [])
  end

  defp do_parse_sequence([], _source, _stops, items, issues) do
    {:ok, Enum.reverse(items), [], Enum.reverse(issues)}
  end

  defp do_parse_sequence([line | rest] = lines, source, stops, items, issues) do
    text = String.trim(line.text)

    cond do
      ignorable_body_line?(text) ->
        do_parse_sequence(rest, source, stops, items, issues)

      command_name(text) in stops ->
        {:ok, Enum.reverse(items), lines, Enum.reverse(issues)}

      String.starts_with?(text, "->") ->
        with {:ok, options, remaining, option_issues} <- parse_options(lines, source) do
          do_parse_sequence(
            remaining,
            source,
            stops,
            [{:options, options, metadata(line, source)} | items],
            Enum.reverse(option_issues, issues)
          )
        end

      command_name(text) == "if" ->
        with {:ok, conditional, remaining, conditional_issues} <- parse_if(lines, source) do
          do_parse_sequence(
            remaining,
            source,
            stops,
            [conditional | items],
            Enum.reverse(conditional_issues, issues)
          )
        end

      String.starts_with?(text, "<<") and not String.ends_with?(text, ">>") ->
        {:error, :invalid_yarn_command}

      String.starts_with?(text, "<<") ->
        {name, args} = split_command(text)
        item = {:command, name, args, metadata(line, source)}
        do_parse_sequence(rest, source, stops, [item | items], issues)

      true ->
        {dialogue, line_id} = strip_line_id(text)
        meta = line |> metadata(source) |> Map.put(:line_id, line_id)
        issues = add_inline_line_issues(issues, text, source, line.line)
        do_parse_sequence(rest, source, stops, [{:line, dialogue, meta} | items], issues)
    end
  end

  defp add_inline_line_issues(issues, text, source, line) do
    issues
    |> maybe_add_issue(
      String.starts_with?(text, "=>"),
      :error,
      :unsupported_yarn_line_group,
      source,
      line
    )
    |> maybe_add_issue(
      inline_once?(text),
      :error,
      :unsupported_yarn_control_command,
      source,
      line
    )
    |> maybe_add_issue(
      unsupported_dialogue_inline_command?(text),
      :error,
      :unsupported_yarn_inline_command,
      source,
      line
    )
    |> maybe_add_issue(
      Regex.match?(~r/^\{\$[A-Za-z_][A-Za-z0-9_.]*\}:\s+/, text),
      :warning,
      :dynamic_yarn_speaker,
      source,
      line
    )
    |> add_text_compatibility_warnings(text, source, line)
  end

  defp inline_once?(text), do: Regex.match?(~r/<<\s*(?:once(?:\s+if\b.*?)?|endonce)\s*>>/i, text)

  defp unsupported_dialogue_inline_command?(text) do
    not String.starts_with?(text, "=>") and inline_command?(text) and not inline_once?(text)
  end

  defp unsupported_option_inline_command?(text) do
    ~r/<<.*?>>/U
    |> Regex.scan(text)
    |> Enum.any?(fn [command] ->
      not inline_once?(command) and not Regex.match?(~r/^<<\s*if\s+.+>>$/i, command)
    end)
  end

  defp inline_command?(text), do: Regex.match?(~r/<<.*?>>/U, text)

  defp add_text_compatibility_warnings(issues, text, source, line) do
    issues
    |> maybe_add_issue(
      unsupported_interpolation?(text),
      :warning,
      :unsupported_yarn_interpolation,
      source,
      line
    )
    |> maybe_add_issue(
      Regex.match?(~r/\[\/?[A-Za-z_][A-Za-z0-9_-]*(?:[=\s][^\]]*)?\]/, text),
      :warning,
      :unsupported_yarn_markup,
      source,
      line
    )
    |> maybe_add_issue(
      Regex.match?(~r/(?:^|\s)#(?!line:)[A-Za-z_][A-Za-z0-9_-]*(?::\S+)?(?:\s|$)/i, text),
      :warning,
      :unsupported_yarn_tag,
      source,
      line
    )
  end

  defp unsupported_interpolation?(text) do
    ~r/\{([^{}\n]+)\}/
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.any?(fn [expression] ->
      not Regex.match?(~r/^\$[A-Za-z_][A-Za-z0-9_.]*$/, String.trim(expression))
    end)
  end

  defp maybe_add_issue(issues, false, _severity, _code, _source, _line), do: issues

  defp maybe_add_issue(issues, true, severity, code, source, line) do
    [ImportIssue.new(severity, code, source: source, line: line) | issues]
  end

  defp parse_options([first | _rest] = lines, source) do
    option_indent = first.indent
    do_parse_options(lines, source, option_indent, [], [])
  end

  defp do_parse_options([line | rest], source, indent, options, issues) do
    text = String.trim(line.text)

    if line.indent == indent and String.starts_with?(text, "->") do
      issues =
        issues
        |> maybe_add_issue(
          inline_once?(text),
          :error,
          :unsupported_yarn_control_command,
          source,
          line.line
        )
        |> maybe_add_issue(
          unsupported_option_inline_command?(text),
          :error,
          :unsupported_yarn_inline_command,
          source,
          line.line
        )
        |> add_text_compatibility_warnings(text, source, line.line)

      {label, line_id} = text |> String.trim_leading("->") |> String.trim() |> strip_line_id()
      {branch_lines, remaining} = Enum.split_while(rest, &(&1.indent > indent))

      with {:ok, body, [], branch_issues} <- parse_sequence(branch_lines, source, []) do
        option = %{
          text: label,
          line_id: line_id,
          body: body,
          source: source,
          line: line.line
        }

        do_parse_options(
          remaining,
          source,
          indent,
          [option | options],
          Enum.reverse(branch_issues, issues)
        )
      end
    else
      {:ok, Enum.reverse(options), [line | rest], Enum.reverse(issues)}
    end
  end

  defp do_parse_options([], _source, _indent, options, issues) do
    {:ok, Enum.reverse(options), [], Enum.reverse(issues)}
  end

  defp parse_if([line | rest], source) do
    {_name, condition} = split_command(String.trim(line.text))

    with {:ok, body, remaining, issues} <- parse_sequence(rest, source, ["elseif", "else", "endif"]),
         {:ok, branches, else_body, remaining, more_issues} <-
           parse_conditional_tail(
             remaining,
             source,
             [%{condition: condition, body: body, meta: metadata(line, source)}],
             issues
           ) do
      item = {:if, branches, else_body, metadata(line, source)}
      {:ok, item, remaining, more_issues}
    end
  end

  defp parse_conditional_tail([], _source, _branches, _issues), do: {:error, :missing_yarn_endif}

  defp parse_conditional_tail([line | rest], source, branches, issues) do
    text = String.trim(line.text)

    case split_command(text) do
      {"elseif", condition} ->
        with {:ok, body, remaining, branch_issues} <-
               parse_sequence(rest, source, ["elseif", "else", "endif"]) do
          parse_conditional_tail(
            remaining,
            source,
            branches ++ [%{condition: condition, body: body, meta: metadata(line, source)}],
            issues ++ branch_issues
          )
        end

      {"else", _args} ->
        with {:ok, body, remaining, else_issues} <- parse_sequence(rest, source, ["endif"]),
             [{_endif_line, tail}] <- [pop_endif(remaining)] do
          {:ok, branches, body, tail, issues ++ else_issues}
        else
          _other -> {:error, :missing_yarn_endif}
        end

      {"endif", _args} ->
        {:ok, branches, [], rest, issues}

      _other ->
        {:error, :invalid_yarn_conditional}
    end
  end

  defp pop_endif([line | rest]) do
    if command_name(String.trim(line.text)) == "endif", do: {line, rest}
  end

  defp pop_endif(_lines), do: nil

  defp split_command(text) do
    command =
      text
      |> String.trim_leading("<<")
      |> String.trim_trailing(">>")
      |> String.trim()

    case String.split(command, ~r/\s+/, parts: 2) do
      [name, args] -> {String.downcase(name), String.trim(args)}
      [name] -> {String.downcase(name), ""}
    end
  end

  defp command_name(text) do
    if String.starts_with?(text, "<<") and String.ends_with?(text, ">>"),
      do: text |> split_command() |> elem(0)
  end

  defp strip_line_id(text) do
    case Regex.run(~r/\s+#line:([A-Za-z0-9_-]+)(?:\s+.*)?$/, text, capture: :all_but_first) do
      [line_id] -> {Regex.replace(~r/\s+#line:[A-Za-z0-9_-]+(?:\s+.*)?$/, text, ""), line_id}
      _other -> {text, nil}
    end
  end

  defp indentation(text) do
    indentation(text, 0)
  end

  defp indentation(<<" ", rest::binary>>, count), do: indentation(rest, count + 1)
  defp indentation(<<"\t", rest::binary>>, count), do: indentation(rest, count + 2)
  defp indentation(_rest, count), do: count

  defp metadata(line, source), do: %{source: source, line: line.line}

  defp ignorable_outside_node?(line) do
    text = String.trim(line.text)
    text == "" or String.starts_with?(text, "//")
  end

  defp ignorable_body_line?(text), do: text == "" or String.starts_with?(text, "//")
end
