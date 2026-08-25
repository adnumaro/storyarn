defmodule Storyarn.Architecture.AccountsWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  @accounts_web_sources ["lib/storyarn_web/controllers/user_session_controller.ex"] ++
                          Path.wildcard("lib/storyarn_web/live/user_live/**/*.ex") ++
                          [
                            "lib/storyarn_web/live/settings_live/profile.ex",
                            "lib/storyarn_web/live/settings_live/security.ex",
                            "lib/storyarn_web/live/settings_live/sudo.ex"
                          ]

  @accounts_domain_sources [
    "lib/storyarn/accounts.ex"
    | Path.wildcard("lib/storyarn/accounts/**/*.ex")
  ]

  test "Accounts Web enters the bounded context only through Storyarn.Accounts" do
    violations =
      @accounts_web_sources
      |> Enum.flat_map(&internal_accounts_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb account pages may call only the public Storyarn.Accounts facade.
    Move the operation behind Storyarn.Accounts instead of importing an Accounts internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Accounts domain does not depend on StoryarnWeb" do
    violations =
      @accounts_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Accounts cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Accounts Web cannot publish generic business facts" do
    violations =
      Enum.filter(@accounts_web_sources, fn path ->
        Regex.match?(
          ~r/\bAccounts(?:\.[A-Z][A-Za-z0-9_]*)*\.Events\b/,
          File.read!(path)
        )
      end)

    refute File.read!("lib/storyarn/accounts.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Account commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  defp internal_accounts_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = accounts_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_accounts_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp accounts_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Accounts]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Accounts]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _ -> :Accounts
            end

          {node, MapSet.put(aliases, alias_name)}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp module_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, aliases ->
          {node, [%{segments: segments, line: meta[:line]} | aliases]}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp internal_accounts_alias?([:Storyarn, :Accounts, _internal | _rest], _local_aliases), do: true

  defp internal_accounts_alias?([local_alias, _internal | _rest], local_aliases),
    do: MapSet.member?(local_aliases, local_alias)

  defp internal_accounts_alias?(_segments, _local_aliases), do: false

  defp grouped_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Accounts\.\{/, line) do
        ["#{path}:#{line_number}: #{String.trim(line)}"]
      else
        []
      end
    end)
  end

  defp storyarn_web_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    ast
    |> module_aliases()
    |> Enum.filter(&match?([:StoryarnWeb | _rest], &1.segments))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Enum.uniq()
  end
end
