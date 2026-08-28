defmodule Storyarn.Localization.Exchange.Queries.Exports do
  @moduledoc false

  alias Storyarn.Localization.Exchange.Rules.Csv
  alias Storyarn.Localization.Texts

  @spec csv(integer(), keyword()) :: {:ok, String.t()}
  def csv(project_id, opts) do
    project_id
    |> Texts.list_texts(opts)
    |> Csv.encode()
  end
end
