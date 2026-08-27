defmodule Storyarn.Sheets.References.Queries.VariableNamespaces do
  @moduledoc false

  @doc false
  defmacro authoritative_owner?(sheet) do
    quote do
      fragment(
        """
        (? IS NOT NULL OR NOT EXISTS (
          SELECT 1
          FROM sheets AS sheet_reference_namespace_owner
          WHERE sheet_reference_namespace_owner.project_id = ?
            AND sheet_reference_namespace_owner.deleted_at IS NULL
            AND sheet_reference_namespace_owner.shortcut = CAST(? AS TEXT)
        ))
        """,
        unquote(sheet).shortcut,
        unquote(sheet).project_id,
        unquote(sheet).id
      )
    end
  end
end
