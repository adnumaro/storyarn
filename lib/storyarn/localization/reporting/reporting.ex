defmodule Storyarn.Localization.Reporting do
  @moduledoc "Internal read-side boundary for Localization reports."

  alias Storyarn.Localization.Reporting.Queries.Reports

  defdelegate progress_by_language(project_id), to: Reports
  defdelegate word_counts_by_speaker(project_id, locale_code), to: Reports
  defdelegate vo_progress(project_id, locale_code), to: Reports
  defdelegate counts_by_source_type(project_id, locale_code), to: Reports
end
