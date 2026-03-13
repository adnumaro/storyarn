defmodule Storyarn.Shared.FormulaEngine do
  @moduledoc """
  Math expression parser, evaluator, and LaTeX generator for table formula columns.

  Parses expressions like `(a - 3) * 2 + 10` into an AST, extracts symbol names
  for binding UI, evaluates with resolved values, and generates LaTeX for display.

  ## Supported syntax

  - Operators: `+`, `-`, `*`, `/`, `^` (with standard precedence)
  - Unary minus: `-a`
  - Parentheses: `(expr)`
  - Literals: integers and floats (`42`, `3.14`)
  - Symbols: `a`, `con_value`, `x1` (lowercase, underscores, digits after first char)
  - Functions: `sqrt(x)`, `abs(x)`, `floor(x)`, `ceil(x)`, `round(x)`, `min(a, b)`, `max(a, b)`
  """

  @type ast ::
          {:number, float()}
          | {:symbol, String.t()}
          | {:binary_op, :add | :sub | :mul | :div | :pow, ast(), ast()}
          | {:unary_op, :neg, ast()}
          | {:func, atom(), [ast()]}

  @known_functions ~w(sqrt abs floor ceil round min max)a

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc "Parse expression string to AST."
  @spec parse(String.t()) :: {:ok, ast()} | {:error, String.t()}
  def parse(expression) when is_binary(expression) do
    expression = String.trim(expression)

    if expression == "" do
      {:error, "Empty expression"}
    else
      with {:ok, tokens} <- tokenize(expression),
           {:ok, ast, []} <- parse_expression(tokens) do
        {:ok, ast}
      else
        {:ok, _ast, remaining} -> {:error, "Unexpected token: #{inspect_token(hd(remaining))}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def parse(_), do: {:error, "Expression must be a string"}

  @doc "Extract all symbol names from a parsed AST. Sorted, deduplicated."
  @spec extract_symbols(ast()) :: [String.t()]
  def extract_symbols(ast) do
    ast
    |> collect_symbols()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Evaluate AST with resolved symbol values."
  @spec evaluate(ast(), %{String.t() => number()}) :: {:ok, number()} | {:error, String.t()}
  def evaluate(ast, values) when is_map(values) do
    eval_node(ast, values)
  end

  @doc "Parse + evaluate in one call."
  @spec compute(String.t(), %{String.t() => number()}) :: {:ok, number()} | {:error, String.t()}
  def compute(expression, values) do
    case parse(expression) do
      {:ok, ast} -> evaluate(ast, values)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Generate LaTeX string from AST."
  @spec to_latex(ast()) :: String.t()
  def to_latex(ast) do
    ast_to_latex(ast)
  end

  @doc "Generate LaTeX string from AST with symbols replaced by their resolved numeric values."
  @spec to_latex_substituted(ast(), %{String.t() => number()}) :: String.t()
  def to_latex_substituted(ast, values) when is_map(values) do
    ast
    |> substitute_symbols(values)
    |> ast_to_latex()
  end

  defp substitute_symbols({:symbol, name} = node, values) do
    case Map.fetch(values, name) do
      {:ok, n} when is_number(n) -> {:number, n / 1}
      _ -> node
    end
  end

  defp substitute_symbols({:binary_op, op, left, right}, values) do
    {:binary_op, op, substitute_symbols(left, values), substitute_symbols(right, values)}
  end

  defp substitute_symbols({:unary_op, op, arg}, values) do
    {:unary_op, op, substitute_symbols(arg, values)}
  end

  defp substitute_symbols({:func, name, args}, values) do
    {:func, name, Enum.map(args, &substitute_symbols(&1, values))}
  end

  defp substitute_symbols(node, _values), do: node

  # ===========================================================================
  # Tokenizer
  # ===========================================================================

  @type token ::
          {:number, float()}
          | {:symbol, String.t()}
          | :lparen
          | :rparen
          | :comma
          | :plus
          | :minus
          | :star
          | :slash
          | :caret

  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, String.t()}
  defp tokenize(input) do
    tokenize(input, [])
  end

  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  # Whitespace — skip
  defp tokenize(<<c, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?\r] do
    tokenize(rest, acc)
  end

  # Single-char tokens
  defp tokenize(<<"(", rest::binary>>, acc), do: tokenize(rest, [:lparen | acc])
  defp tokenize(<<")", rest::binary>>, acc), do: tokenize(rest, [:rparen | acc])
  defp tokenize(<<",", rest::binary>>, acc), do: tokenize(rest, [:comma | acc])
  defp tokenize(<<"+", rest::binary>>, acc), do: tokenize(rest, [:plus | acc])
  defp tokenize(<<"-", rest::binary>>, acc), do: tokenize(rest, [:minus | acc])
  defp tokenize(<<"*", rest::binary>>, acc), do: tokenize(rest, [:star | acc])
  defp tokenize(<<"/", rest::binary>>, acc), do: tokenize(rest, [:slash | acc])
  defp tokenize(<<"^", rest::binary>>, acc), do: tokenize(rest, [:caret | acc])

  # Number: digits with optional decimal point
  defp tokenize(<<c, _rest::binary>> = input, acc) when c in ?0..?9 do
    {num_str, rest} = consume_number(input)

    case Float.parse(num_str) do
      {n, ""} -> tokenize(rest, [{:number, n} | acc])
      _ -> {:error, "Invalid number: #{num_str}"}
    end
  end

  # Number starting with decimal point: .5
  defp tokenize(<<".", c, _rest::binary>> = input, acc) when c in ?0..?9 do
    {num_str, rest} = consume_number(input)

    case Float.parse(num_str) do
      {n, ""} -> tokenize(rest, [{:number, n} | acc])
      _ -> {:error, "Invalid number: #{num_str}"}
    end
  end

  # Symbol: lowercase letters, underscores, digits after first char
  defp tokenize(<<c, _rest::binary>> = input, acc) when c in ?a..?z or c == ?_ do
    {sym, rest} = consume_symbol(input)
    tokenize(rest, [{:symbol, sym} | acc])
  end

  defp tokenize(<<c::utf8, _rest::binary>>, _acc) do
    char = <<c::utf8>>
    {:error, "Unexpected character: '#{char}'"}
  end

  defp consume_number(input), do: consume_while(input, &number_char?/1)

  defp number_char?(c), do: c in ?0..?9 or c == ?.

  defp consume_symbol(input), do: consume_while(input, &symbol_char?/1)

  defp symbol_char?(c), do: c in ?a..?z or c in ?0..?9 or c == ?_

  defp consume_while(input, pred) do
    consume_while(input, pred, <<>>)
  end

  defp consume_while(<<c, rest::binary>>, pred, acc) do
    if pred.(c) do
      consume_while(rest, pred, <<acc::binary, c>>)
    else
      {acc, <<c, rest::binary>>}
    end
  end

  defp consume_while(<<>>, _pred, acc), do: {acc, <<>>}

  # ===========================================================================
  # Parser (recursive descent)
  # ===========================================================================

  # expression = additive
  defp parse_expression(tokens) do
    parse_additive(tokens)
  end

  # additive = multiplicative (('+' | '-') multiplicative)*
  defp parse_additive(tokens) do
    with {:ok, left, rest} <- parse_multiplicative(tokens) do
      parse_additive_rest(left, rest)
    end
  end

  defp parse_additive_rest(left, [:plus | rest]) do
    with {:ok, right, rest2} <- parse_multiplicative(rest) do
      parse_additive_rest({:binary_op, :add, left, right}, rest2)
    end
  end

  defp parse_additive_rest(left, [:minus | rest]) do
    with {:ok, right, rest2} <- parse_multiplicative(rest) do
      parse_additive_rest({:binary_op, :sub, left, right}, rest2)
    end
  end

  defp parse_additive_rest(left, rest), do: {:ok, left, rest}

  # multiplicative = power (('*' | '/') power)*
  defp parse_multiplicative(tokens) do
    with {:ok, left, rest} <- parse_power(tokens) do
      parse_multiplicative_rest(left, rest)
    end
  end

  defp parse_multiplicative_rest(left, [:star | rest]) do
    with {:ok, right, rest2} <- parse_power(rest) do
      parse_multiplicative_rest({:binary_op, :mul, left, right}, rest2)
    end
  end

  defp parse_multiplicative_rest(left, [:slash | rest]) do
    with {:ok, right, rest2} <- parse_power(rest) do
      parse_multiplicative_rest({:binary_op, :div, left, right}, rest2)
    end
  end

  defp parse_multiplicative_rest(left, rest), do: {:ok, left, rest}

  # power = unary ('^' power)?   — right-associative
  defp parse_power(tokens) do
    with {:ok, base, rest} <- parse_unary(tokens) do
      parse_power_rest(base, rest)
    end
  end

  defp parse_power_rest(base, [:caret | rest]) do
    with {:ok, exponent, rest2} <- parse_power(rest) do
      {:ok, {:binary_op, :pow, base, exponent}, rest2}
    end
  end

  defp parse_power_rest(base, rest), do: {:ok, base, rest}

  # unary = '-' unary | primary
  defp parse_unary([:minus | rest]) do
    with {:ok, arg, rest2} <- parse_unary(rest) do
      {:ok, {:unary_op, :neg, arg}, rest2}
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  # primary = NUMBER | SYMBOL '(' args ')' | SYMBOL | '(' expression ')'
  defp parse_primary([{:number, n} | rest]) do
    {:ok, {:number, n}, rest}
  end

  @known_functions_map Map.new(@known_functions, fn a -> {Atom.to_string(a), a} end)

  defp parse_primary([{:symbol, name}, :lparen | rest]) do
    case Map.fetch(@known_functions_map, name) do
      {:ok, func_atom} ->
        with {:ok, args, rest2} <- parse_args(rest),
             [:rparen | rest3] <- wrap_expect_rparen(rest2) do
          {:ok, {:func, func_atom, args}, rest3}
        else
          :missing_rparen -> {:error, "Missing closing parenthesis for #{name}()"}
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, "Unknown function: #{name}"}
    end
  end

  defp parse_primary([{:symbol, name} | rest]) do
    {:ok, {:symbol, name}, rest}
  end

  defp parse_primary([:lparen | rest]) do
    with {:ok, expr, rest2} <- parse_expression(rest) do
      case rest2 do
        [:rparen | rest3] -> {:ok, expr, rest3}
        _ -> {:error, "Missing closing parenthesis"}
      end
    end
  end

  defp parse_primary([]) do
    {:error, "Unexpected end of expression"}
  end

  defp parse_primary([token | _]) do
    {:error, "Unexpected token: #{inspect_token(token)}"}
  end

  # args = expression (',' expression)*
  defp parse_args(tokens) do
    with {:ok, first, rest} <- parse_expression(tokens) do
      parse_args_rest([first], rest)
    end
  end

  defp parse_args_rest(acc, [:comma | rest]) do
    with {:ok, arg, rest2} <- parse_expression(rest) do
      parse_args_rest(acc ++ [arg], rest2)
    end
  end

  defp parse_args_rest(acc, rest), do: {:ok, acc, rest}

  defp wrap_expect_rparen([:rparen | rest]), do: [:rparen | rest]
  defp wrap_expect_rparen(_), do: :missing_rparen

  defp inspect_token({:number, n}), do: "number #{n}"
  defp inspect_token({:symbol, s}), do: "'#{s}'"
  defp inspect_token(:lparen), do: "'('"
  defp inspect_token(:rparen), do: "')'"
  defp inspect_token(:comma), do: "','"
  defp inspect_token(:plus), do: "'+'"
  defp inspect_token(:minus), do: "'-'"
  defp inspect_token(:star), do: "'*'"
  defp inspect_token(:slash), do: "'/'"
  defp inspect_token(:caret), do: "'^'"
  defp inspect_token(other), do: inspect(other)

  # ===========================================================================
  # Symbol Extraction
  # ===========================================================================

  defp collect_symbols({:number, _}), do: []
  defp collect_symbols({:symbol, name}), do: [name]

  defp collect_symbols({:binary_op, _op, left, right}) do
    collect_symbols(left) ++ collect_symbols(right)
  end

  defp collect_symbols({:unary_op, _op, arg}), do: collect_symbols(arg)

  defp collect_symbols({:func, _name, args}) do
    Enum.flat_map(args, &collect_symbols/1)
  end

  # ===========================================================================
  # Evaluator
  # ===========================================================================

  defp eval_node({:number, n}, _values), do: {:ok, n / 1}

  defp eval_node({:symbol, name}, values) do
    case Map.fetch(values, name) do
      {:ok, n} when is_number(n) -> {:ok, n / 1}
      {:ok, nil} -> {:error, "Symbol '#{name}' is nil"}
      {:ok, _} -> {:error, "Symbol '#{name}' is not a number"}
      :error -> {:error, "Unbound symbol '#{name}'"}
    end
  end

  defp eval_node({:binary_op, op, left, right}, values) do
    with {:ok, l} <- eval_node(left, values),
         {:ok, r} <- eval_node(right, values) do
      case op do
        :add -> {:ok, l + r}
        :sub -> {:ok, l - r}
        :mul -> {:ok, l * r}
        :div when r == 0.0 -> {:error, "Division by zero"}
        :div when r == 0 -> {:error, "Division by zero"}
        :div -> {:ok, l / r}
        :pow -> {:ok, :math.pow(l, r)}
      end
    end
  end

  defp eval_node({:unary_op, :neg, arg}, values) do
    with {:ok, n} <- eval_node(arg, values), do: {:ok, -n}
  end

  # Single-arg functions
  defp eval_node({:func, :sqrt, [arg]}, values) do
    with {:ok, n} <- eval_node(arg, values) do
      if n < 0, do: {:error, "Square root of negative number"}, else: {:ok, :math.sqrt(n)}
    end
  end

  defp eval_node({:func, :abs, [arg]}, values) do
    with {:ok, n} <- eval_node(arg, values), do: {:ok, abs(n)}
  end

  defp eval_node({:func, :floor, [arg]}, values) do
    with {:ok, n} <- eval_node(arg, values), do: {:ok, Float.floor(n)}
  end

  defp eval_node({:func, :ceil, [arg]}, values) do
    with {:ok, n} <- eval_node(arg, values), do: {:ok, Float.ceil(n)}
  end

  defp eval_node({:func, :round, [arg]}, values) do
    with {:ok, n} <- eval_node(arg, values), do: {:ok, Float.round(n)}
  end

  # Two-arg functions
  defp eval_node({:func, :min, [a, b]}, values) do
    with {:ok, va} <- eval_node(a, values),
         {:ok, vb} <- eval_node(b, values),
         do: {:ok, min(va, vb)}
  end

  defp eval_node({:func, :max, [a, b]}, values) do
    with {:ok, va} <- eval_node(a, values),
         {:ok, vb} <- eval_node(b, values),
         do: {:ok, max(va, vb)}
  end

  defp eval_node({:func, name, args}, _values) do
    {:error, "Function #{name} expects different number of arguments (got #{length(args)})"}
  end

  # ===========================================================================
  # LaTeX Generator
  # ===========================================================================

  defp ast_to_latex({:number, n}) do
    if n == Float.floor(n) and n >= -1.0e15 and n <= 1.0e15 do
      Integer.to_string(trunc(n))
    else
      Float.to_string(n)
    end
  end

  defp ast_to_latex({:symbol, s}), do: s

  defp ast_to_latex({:binary_op, :add, l, r}),
    do: "#{ast_to_latex(l)} + #{ast_to_latex(r)}"

  defp ast_to_latex({:binary_op, :sub, l, r}),
    do: "#{ast_to_latex(l)} - #{ast_to_latex(r)}"

  defp ast_to_latex({:binary_op, :mul, l, r}),
    do: "#{wrap_if_additive(l)} \\times #{wrap_if_additive(r)}"

  defp ast_to_latex({:binary_op, :div, l, r}),
    do: "\\frac{#{ast_to_latex(l)}}{#{ast_to_latex(r)}}"

  defp ast_to_latex({:binary_op, :pow, l, r}),
    do: "{#{wrap_if_complex(l)}}^{#{ast_to_latex(r)}}"

  defp ast_to_latex({:unary_op, :neg, arg}),
    do: "-#{wrap_if_complex(arg)}"

  defp ast_to_latex({:func, :sqrt, [arg]}),
    do: "\\sqrt{#{ast_to_latex(arg)}}"

  defp ast_to_latex({:func, name, args}),
    do: "\\mathrm{#{name}}(#{Enum.map_join(args, ", ", &ast_to_latex/1)})"

  # Wrap in parens if the sub-expression is additive (for multiplication display)
  defp wrap_if_additive({:binary_op, op, _, _} = ast) when op in [:add, :sub],
    do: "(#{ast_to_latex(ast)})"

  defp wrap_if_additive(ast), do: ast_to_latex(ast)

  # Wrap in parens if the sub-expression has operators (for power base, negation)
  defp wrap_if_complex({:binary_op, _, _, _} = ast), do: "(#{ast_to_latex(ast)})"
  defp wrap_if_complex({:unary_op, _, _} = ast), do: "(#{ast_to_latex(ast)})"
  defp wrap_if_complex(ast), do: ast_to_latex(ast)
end
