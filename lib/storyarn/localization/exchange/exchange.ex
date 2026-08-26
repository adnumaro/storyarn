defmodule Storyarn.Localization.Exchange do
  @moduledoc """
  Internal capability boundary for translator-facing exchange formats.

  The root Localization facade delegates here. CSV parsing, XLSX encoding and
  import mutations remain behind their explicit role folders.
  """

  alias Storyarn.Localization.Exchange.Adapters.Xlsx.Encoder
  alias Storyarn.Localization.Exchange.Commands.ImportCsv
  alias Storyarn.Localization.Exchange.Queries.Exports
  alias Storyarn.Localization.Texts

  def export_xlsx(project_id, opts) do
    project_id
    |> Texts.list_texts(opts)
    |> Encoder.encode()
  end

  defdelegate export_csv(project_id, opts), to: Exports, as: :csv
  defdelegate import_csv(project_id, csv_content), to: ImportCsv, as: :import

  defdelegate list_texts_for_export(project_id, locale_codes, opts \\ []), to: Texts
  defdelegate list_texts_for_canonical_snapshot(project_id), to: Texts
  defdelegate texts_for_export_query(project_id, locale_codes, opts \\ []), to: Texts
  defdelegate list_texts_for_backup(project_id, locale_codes), to: Texts
  defdelegate count_texts_for_export(project_id, locale_codes, opts \\ []), to: Texts
  defdelegate list_target_locale_codes(project_id), to: Texts
  defdelegate bulk_import_texts(attrs_list), to: Texts
end
