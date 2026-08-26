defmodule Storyarn.Projects.References.VariableNamespaceResolver do
  @moduledoc """
  Resolves the canonical namespace used by persisted variable references.

  Explicit shortcuts are authoritative. Shortcutless Sheets fall back to
  their decimal ID only when no active Sheet owns that string explicitly.
  """

  import Ecto.Query

  alias Storyarn.Projects.References.Persistence.SheetRecord
  alias Storyarn.Repo

  @max_bigint 9_223_372_036_854_775_807

  @doc false
  defmacro authoritative_namespace_owner?(sheet) do
    quote do
      fragment(
        """
        (? IS NOT NULL OR NOT EXISTS (
          SELECT 1
          FROM sheets AS variable_namespace_owner
          WHERE variable_namespace_owner.project_id = ?
            AND variable_namespace_owner.deleted_at IS NULL
            AND variable_namespace_owner.shortcut = CAST(? AS TEXT)
        ))
        """,
        unquote(sheet).shortcut,
        unquote(sheet).project_id,
        unquote(sheet).id
      )
    end
  end

  @spec resolve_sheet_id(pos_integer(), String.t()) :: pos_integer() | nil
  def resolve_sheet_id(project_id, namespace)
      when is_integer(project_id) and project_id > 0 and is_binary(namespace) and namespace != "" do
    project_id
    |> resolve_sheet_ids([namespace])
    |> Map.get(namespace)
  end

  def resolve_sheet_id(_project_id, _namespace), do: nil

  @spec resolve_sheet_ids(pos_integer(), [String.t()]) :: %{String.t() => pos_integer()}
  def resolve_sheet_ids(project_id, namespaces) when is_integer(project_id) and project_id > 0 and is_list(namespaces) do
    namespaces = namespaces |> Enum.filter(&valid_namespace?/1) |> Enum.uniq()
    numeric_ids = numeric_namespace_ids(namespaces)

    project_id
    |> namespace_candidates(namespaces, numeric_ids)
    |> authoritative_namespace_ids()
  end

  def resolve_sheet_ids(_project_id, _namespaces), do: %{}

  defp namespace_candidates(_project_id, [], _numeric_ids), do: []

  defp namespace_candidates(project_id, namespaces, numeric_ids) do
    Repo.all(
      from(sheet in SheetRecord,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            (sheet.shortcut in ^namespaces or
               (is_nil(sheet.shortcut) and sheet.id in ^numeric_ids)),
        select: {sheet.shortcut, sheet.id}
      )
    )
  end

  defp authoritative_namespace_ids(candidates) do
    fallback =
      candidates
      |> Enum.filter(fn {shortcut, _id} -> is_nil(shortcut) end)
      |> Map.new(fn {_shortcut, id} -> {Integer.to_string(id), id} end)

    explicit =
      candidates
      |> Enum.reject(fn {shortcut, _id} -> is_nil(shortcut) end)
      |> Map.new()

    Map.merge(fallback, explicit)
  end

  defp numeric_namespace_ids(namespaces) do
    namespaces
    |> Enum.flat_map(fn namespace ->
      case canonical_numeric_id(namespace) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  defp canonical_numeric_id(namespace) do
    with {id, ""} when id > 0 and id <= @max_bigint <- Integer.parse(namespace),
         ^namespace <- Integer.to_string(id) do
      {:ok, id}
    else
      _invalid -> :error
    end
  end

  defp valid_namespace?(namespace), do: is_binary(namespace) and namespace != ""
end
