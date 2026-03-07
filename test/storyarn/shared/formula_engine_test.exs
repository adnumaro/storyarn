defmodule Storyarn.Shared.FormulaEngineTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.FormulaEngine

  # ===========================================================================
  # parse/1
  # ===========================================================================

  describe "parse/1 - basic expressions" do
    test "simple addition" do
      assert {:ok, {:binary_op, :add, {:symbol, "a"}, {:symbol, "b"}}} =
               FormulaEngine.parse("a + b")
    end

    test "simple subtraction" do
      assert {:ok, {:binary_op, :sub, {:symbol, "a"}, {:number, 3.0}}} =
               FormulaEngine.parse("a - 3")
    end

    test "simple multiplication" do
      assert {:ok, {:binary_op, :mul, {:symbol, "a"}, {:symbol, "b"}}} =
               FormulaEngine.parse("a * b")
    end

    test "simple division" do
      assert {:ok, {:binary_op, :div, {:symbol, "a"}, {:symbol, "b"}}} =
               FormulaEngine.parse("a / b")
    end

    test "numeric literal integer" do
      assert {:ok, {:number, 42.0}} = FormulaEngine.parse("42")
    end

    test "numeric literal float" do
      assert {:ok, {:number, 3.14}} = FormulaEngine.parse("3.14")
    end

    test "symbol with underscores and digits" do
      assert {:ok, {:symbol, "con_value"}} = FormulaEngine.parse("con_value")
      assert {:ok, {:symbol, "x1"}} = FormulaEngine.parse("x1")
    end
  end

  describe "parse/1 - operator precedence" do
    test "multiplication binds tighter than addition" do
      {:ok, ast} = FormulaEngine.parse("a + b * c")

      assert {:binary_op, :add, {:symbol, "a"},
              {:binary_op, :mul, {:symbol, "b"}, {:symbol, "c"}}} = ast
    end

    test "division binds tighter than subtraction" do
      {:ok, ast} = FormulaEngine.parse("a - b / c")

      assert {:binary_op, :sub, {:symbol, "a"},
              {:binary_op, :div, {:symbol, "b"}, {:symbol, "c"}}} = ast
    end

    test "parentheses override precedence" do
      {:ok, ast} = FormulaEngine.parse("(a + b) * c")

      assert {:binary_op, :mul, {:binary_op, :add, {:symbol, "a"}, {:symbol, "b"}},
              {:symbol, "c"}} = ast
    end

    test "exponentiation binds tighter than multiplication" do
      {:ok, ast} = FormulaEngine.parse("a * b ^ c")

      assert {:binary_op, :mul, {:symbol, "a"},
              {:binary_op, :pow, {:symbol, "b"}, {:symbol, "c"}}} = ast
    end

    test "exponentiation is right-associative" do
      {:ok, ast} = FormulaEngine.parse("a ^ b ^ c")

      assert {:binary_op, :pow, {:symbol, "a"},
              {:binary_op, :pow, {:symbol, "b"}, {:symbol, "c"}}} = ast
    end
  end

  describe "parse/1 - unary minus" do
    test "unary minus on symbol" do
      assert {:ok, {:unary_op, :neg, {:symbol, "a"}}} = FormulaEngine.parse("-a")
    end

    test "unary minus on number" do
      assert {:ok, {:unary_op, :neg, {:number, 3.0}}} = FormulaEngine.parse("-3")
    end

    test "double unary minus" do
      assert {:ok, {:unary_op, :neg, {:unary_op, :neg, {:symbol, "a"}}}} =
               FormulaEngine.parse("--a")
    end

    test "unary minus in expression" do
      {:ok, ast} = FormulaEngine.parse("a + -b")
      assert {:binary_op, :add, {:symbol, "a"}, {:unary_op, :neg, {:symbol, "b"}}} = ast
    end
  end

  describe "parse/1 - function calls" do
    test "single arg function" do
      assert {:ok, {:func, :sqrt, [{:symbol, "a"}]}} = FormulaEngine.parse("sqrt(a)")
    end

    test "two arg function" do
      assert {:ok, {:func, :max, [{:symbol, "a"}, {:symbol, "b"}]}} =
               FormulaEngine.parse("max(a, b)")
    end

    test "nested functions" do
      {:ok, ast} = FormulaEngine.parse("max(a, min(b, c))")

      assert {:func, :max, [{:symbol, "a"}, {:func, :min, [{:symbol, "b"}, {:symbol, "c"}]}]} =
               ast
    end

    test "function with expression arg" do
      {:ok, ast} = FormulaEngine.parse("sqrt(a + b)")
      assert {:func, :sqrt, [{:binary_op, :add, {:symbol, "a"}, {:symbol, "b"}}]} = ast
    end

    test "all known functions parse" do
      for func <- ~w(sqrt abs floor ceil round) do
        assert {:ok, {:func, _, [{:symbol, "x"}]}} = FormulaEngine.parse("#{func}(x)")
      end

      for func <- ~w(min max) do
        assert {:ok, {:func, _, [{:symbol, "x"}, {:symbol, "y"}]}} =
                 FormulaEngine.parse("#{func}(x, y)")
      end
    end
  end

  describe "parse/1 - complex expressions" do
    test "modifier formula: a - 3" do
      assert {:ok, _} = FormulaEngine.parse("a - 3")
    end

    test "PV formula: 10 + a * 2" do
      {:ok, ast} = FormulaEngine.parse("10 + a * 2")

      assert {:binary_op, :add, {:number, 10.0},
              {:binary_op, :mul, {:symbol, "a"}, {:number, 2.0}}} = ast
    end

    test "evasion formula: 8 + a - 3" do
      assert {:ok, _} = FormulaEngine.parse("8 + a - 3")
    end

    test "quadratic-like: (a - 3) * 2 + 10" do
      assert {:ok, _} = FormulaEngine.parse("(a - 3) * 2 + 10")
    end

    test "whitespace is ignored" do
      assert {:ok, _} = FormulaEngine.parse("  a  +  b  ")
    end
  end

  describe "parse/1 - errors" do
    test "empty string" do
      assert {:error, "Empty expression"} = FormulaEngine.parse("")
    end

    test "whitespace only" do
      assert {:error, "Empty expression"} = FormulaEngine.parse("   ")
    end

    test "unmatched open paren" do
      assert {:error, _} = FormulaEngine.parse("(a + b")
    end

    test "unknown function" do
      assert {:error, "Unknown function: foo"} = FormulaEngine.parse("foo(a)")
    end

    test "trailing operator" do
      assert {:error, _} = FormulaEngine.parse("a +")
    end

    test "leading operator (non-unary)" do
      assert {:error, _} = FormulaEngine.parse("* a")
    end

    test "consecutive binary operators" do
      assert {:error, _} = FormulaEngine.parse("a + * b")
    end

    test "non-string input" do
      assert {:error, _} = FormulaEngine.parse(42)
    end

    test "missing function closing paren" do
      assert {:error, _} = FormulaEngine.parse("sqrt(a")
    end

    test "unexpected character" do
      assert {:error, _} = FormulaEngine.parse("a @ b")
    end
  end

  # ===========================================================================
  # extract_symbols/1
  # ===========================================================================

  describe "extract_symbols/1" do
    test "simple expression" do
      {:ok, ast} = FormulaEngine.parse("a + b")
      assert FormulaEngine.extract_symbols(ast) == ["a", "b"]
    end

    test "no duplicates" do
      {:ok, ast} = FormulaEngine.parse("a + a * a")
      assert FormulaEngine.extract_symbols(ast) == ["a"]
    end

    test "ignores function names" do
      {:ok, ast} = FormulaEngine.parse("sqrt(a)")
      assert FormulaEngine.extract_symbols(ast) == ["a"]
    end

    test "complex expression" do
      {:ok, ast} = FormulaEngine.parse("(x - 3) * y + z")
      assert FormulaEngine.extract_symbols(ast) == ["x", "y", "z"]
    end

    test "no symbols in literal-only expression" do
      {:ok, ast} = FormulaEngine.parse("42 + 3")
      assert FormulaEngine.extract_symbols(ast) == []
    end

    test "sorted alphabetically" do
      {:ok, ast} = FormulaEngine.parse("c + a + b")
      assert FormulaEngine.extract_symbols(ast) == ["a", "b", "c"]
    end

    test "nested function symbols" do
      {:ok, ast} = FormulaEngine.parse("max(x, min(y, z))")
      assert FormulaEngine.extract_symbols(ast) == ["x", "y", "z"]
    end

    test "unary minus symbol" do
      {:ok, ast} = FormulaEngine.parse("-a")
      assert FormulaEngine.extract_symbols(ast) == ["a"]
    end
  end

  # ===========================================================================
  # evaluate/2
  # ===========================================================================

  describe "evaluate/2 - arithmetic" do
    test "addition" do
      {:ok, ast} = FormulaEngine.parse("a + b")
      assert {:ok, 8.0} = FormulaEngine.evaluate(ast, %{"a" => 3, "b" => 5})
    end

    test "subtraction" do
      {:ok, ast} = FormulaEngine.parse("a - b")
      assert {:ok, -2.0} = FormulaEngine.evaluate(ast, %{"a" => 3, "b" => 5})
    end

    test "multiplication" do
      {:ok, ast} = FormulaEngine.parse("a * b")
      assert {:ok, 15.0} = FormulaEngine.evaluate(ast, %{"a" => 3, "b" => 5})
    end

    test "division" do
      {:ok, ast} = FormulaEngine.parse("a / b")
      assert {:ok, 2.5} = FormulaEngine.evaluate(ast, %{"a" => 5, "b" => 2})
    end

    test "division by zero" do
      {:ok, ast} = FormulaEngine.parse("a / b")
      assert {:error, "Division by zero"} = FormulaEngine.evaluate(ast, %{"a" => 5, "b" => 0})
    end

    test "exponentiation" do
      {:ok, ast} = FormulaEngine.parse("a ^ b")
      assert {:ok, 9.0} = FormulaEngine.evaluate(ast, %{"a" => 3, "b" => 2})
    end

    test "unary negation" do
      {:ok, ast} = FormulaEngine.parse("-a")
      assert {:ok, -5.0} = FormulaEngine.evaluate(ast, %{"a" => 5})
    end

    test "numeric literal" do
      {:ok, ast} = FormulaEngine.parse("42")
      assert {:ok, 42.0} = FormulaEngine.evaluate(ast, %{})
    end

    test "complex: modifier formula" do
      assert {:ok, 2.0} = FormulaEngine.compute("a - 3", %{"a" => 5})
    end

    test "complex: PV formula" do
      assert {:ok, 18.0} = FormulaEngine.compute("10 + a * 2", %{"a" => 4})
    end

    test "complex: evasion formula" do
      assert {:ok, 7.0} = FormulaEngine.compute("8 + a - 3", %{"a" => 2})
    end
  end

  describe "evaluate/2 - error handling" do
    test "unbound symbol" do
      {:ok, ast} = FormulaEngine.parse("a + b")
      assert {:error, "Unbound symbol 'b'"} = FormulaEngine.evaluate(ast, %{"a" => 3})
    end

    test "nil symbol" do
      {:ok, ast} = FormulaEngine.parse("a")
      assert {:error, "Symbol 'a' is nil"} = FormulaEngine.evaluate(ast, %{"a" => nil})
    end

    test "non-numeric symbol" do
      {:ok, ast} = FormulaEngine.parse("a")

      assert {:error, "Symbol 'a' is not a number"} =
               FormulaEngine.evaluate(ast, %{"a" => "hello"})
    end
  end

  describe "evaluate/2 - functions" do
    test "sqrt" do
      assert {:ok, 3.0} = FormulaEngine.compute("sqrt(a)", %{"a" => 9})
    end

    test "sqrt of negative" do
      assert {:error, "Square root of negative number"} =
               FormulaEngine.compute("sqrt(a)", %{"a" => -1})
    end

    test "abs positive" do
      assert {:ok, 5.0} = FormulaEngine.compute("abs(a)", %{"a" => 5})
    end

    test "abs negative" do
      assert {:ok, 5.0} = FormulaEngine.compute("abs(a)", %{"a" => -5})
    end

    test "floor" do
      assert {:ok, 3.0} = FormulaEngine.compute("floor(a)", %{"a" => 3.7})
    end

    test "ceil" do
      assert {:ok, 4.0} = FormulaEngine.compute("ceil(a)", %{"a" => 3.2})
    end

    test "round" do
      assert {:ok, 4.0} = FormulaEngine.compute("round(a)", %{"a" => 3.5})
    end

    test "min" do
      assert {:ok, 3.0} = FormulaEngine.compute("min(a, b)", %{"a" => 3, "b" => 5})
    end

    test "max" do
      assert {:ok, 5.0} = FormulaEngine.compute("max(a, b)", %{"a" => 3, "b" => 5})
    end

    test "nested: max with min" do
      assert {:ok, 4.0} =
               FormulaEngine.compute("max(a, min(b, c))", %{"a" => 4, "b" => 2, "c" => 7})
    end
  end

  describe "evaluate/2 - integer and float handling" do
    test "integer inputs produce float results" do
      assert {:ok, result} = FormulaEngine.compute("a + b", %{"a" => 3, "b" => 5})
      assert is_float(result)
    end

    test "float inputs work" do
      assert {:ok, 5.5} = FormulaEngine.compute("a + b", %{"a" => 2.5, "b" => 3.0})
    end
  end

  # ===========================================================================
  # compute/2
  # ===========================================================================

  describe "compute/2" do
    test "convenience wrapper works" do
      assert {:ok, 2.0} = FormulaEngine.compute("a - 3", %{"a" => 5})
    end

    test "parse error propagates" do
      assert {:error, _} = FormulaEngine.compute("(invalid", %{})
    end

    test "eval error propagates" do
      assert {:error, _} = FormulaEngine.compute("a / b", %{"a" => 1, "b" => 0})
    end
  end

  # ===========================================================================
  # to_latex/1
  # ===========================================================================

  describe "to_latex/1" do
    test "number" do
      {:ok, ast} = FormulaEngine.parse("42")
      assert FormulaEngine.to_latex(ast) == "42"
    end

    test "float number" do
      {:ok, ast} = FormulaEngine.parse("3.14")
      assert FormulaEngine.to_latex(ast) =~ "3.14"
    end

    test "symbol" do
      {:ok, ast} = FormulaEngine.parse("a")
      assert FormulaEngine.to_latex(ast) == "a"
    end

    test "addition" do
      {:ok, ast} = FormulaEngine.parse("a + b")
      assert FormulaEngine.to_latex(ast) == "a + b"
    end

    test "subtraction" do
      {:ok, ast} = FormulaEngine.parse("a - 3")
      assert FormulaEngine.to_latex(ast) == "a - 3"
    end

    test "multiplication uses times" do
      {:ok, ast} = FormulaEngine.parse("a * b")
      assert FormulaEngine.to_latex(ast) == "a \\times b"
    end

    test "division as frac" do
      {:ok, ast} = FormulaEngine.parse("a / b")
      assert FormulaEngine.to_latex(ast) == "\\frac{a}{b}"
    end

    test "power" do
      {:ok, ast} = FormulaEngine.parse("a ^ 2")
      assert FormulaEngine.to_latex(ast) == "{a}^{2}"
    end

    test "sqrt" do
      {:ok, ast} = FormulaEngine.parse("sqrt(a)")
      assert FormulaEngine.to_latex(ast) == "\\sqrt{a}"
    end

    test "named function" do
      {:ok, ast} = FormulaEngine.parse("floor(a)")
      assert FormulaEngine.to_latex(ast) == "\\mathrm{floor}(a)"
    end

    test "unary minus" do
      {:ok, ast} = FormulaEngine.parse("-a")
      assert FormulaEngine.to_latex(ast) == "-a"
    end

    test "complex: modifier formula" do
      {:ok, ast} = FormulaEngine.parse("(a - 3) * 2")
      latex = FormulaEngine.to_latex(ast)
      assert latex == "(a - 3) \\times 2"
    end

    test "complex: PV formula with division" do
      {:ok, ast} = FormulaEngine.parse("a / b")
      assert FormulaEngine.to_latex(ast) == "\\frac{a}{b}"
    end
  end

  # ===========================================================================
  # to_latex_substituted/2
  # ===========================================================================

  describe "to_latex_substituted/2" do
    test "replaces symbols with numeric values" do
      {:ok, ast} = FormulaEngine.parse("a * b * 2")
      result = FormulaEngine.to_latex_substituted(ast, %{"a" => 10.0, "b" => 3.0})
      assert result == "10 \\times 3 \\times 2"
    end

    test "keeps unresolved symbols as-is" do
      {:ok, ast} = FormulaEngine.parse("a + b")
      result = FormulaEngine.to_latex_substituted(ast, %{"a" => 5.0})
      assert result == "5 + b"
    end

    test "works with empty values map" do
      {:ok, ast} = FormulaEngine.parse("a + b")
      result = FormulaEngine.to_latex_substituted(ast, %{})
      assert result == "a + b"
    end

    test "works with literal-only expressions" do
      {:ok, ast} = FormulaEngine.parse("2 + 3")
      result = FormulaEngine.to_latex_substituted(ast, %{})
      assert result == "2 + 3"
    end

    test "handles division with substituted values" do
      {:ok, ast} = FormulaEngine.parse("a / b")
      result = FormulaEngine.to_latex_substituted(ast, %{"a" => 10.0, "b" => 2.0})
      assert result == "\\frac{10}{2}"
    end

    test "handles functions with substituted values" do
      {:ok, ast} = FormulaEngine.parse("sqrt(a)")
      result = FormulaEngine.to_latex_substituted(ast, %{"a" => 16.0})
      assert result == "\\sqrt{16}"
    end

    test "handles unary negation with substituted values" do
      {:ok, ast} = FormulaEngine.parse("-a")
      result = FormulaEngine.to_latex_substituted(ast, %{"a" => 5.0})
      assert result == "-5"
    end

    test "handles power with substituted values" do
      {:ok, ast} = FormulaEngine.parse("a ^ 2")
      result = FormulaEngine.to_latex_substituted(ast, %{"a" => 3.0})
      assert result == "{3}^{2}"
    end
  end

  # ===========================================================================
  # parse/1 - UTF-8 error handling
  # ===========================================================================

  describe "parse/1 - UTF-8 characters" do
    test "returns valid UTF-8 error for accented characters" do
      assert {:error, msg} = FormulaEngine.parse("débería")
      assert String.valid?(msg)
      assert msg =~ "Unexpected character"
    end

    test "returns valid UTF-8 error for emoji" do
      assert {:error, msg} = FormulaEngine.parse("x + 🎲")
      assert String.valid?(msg)
    end

    test "returns valid UTF-8 error for CJK characters" do
      assert {:error, msg} = FormulaEngine.parse("变量")
      assert String.valid?(msg)
      assert String.valid?(msg)
    end
  end
end
