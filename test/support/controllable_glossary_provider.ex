defmodule Storyarn.TestSupport.ControllableGlossaryProvider do
  @moduledoc false

  def create_glossary(_name, _source_locale, _target_locale, _entries, _config) do
    send(coordinator!(), {:glossary_created, self(), "new-glossary"})
    {:ok, "new-glossary"}
  end

  def delete_glossary(glossary_id, _config) do
    send(coordinator!(), {:glossary_delete_started, self(), glossary_id})

    receive do
      {:continue_glossary_delete, ^glossary_id} -> :ok
    after
      5_000 -> {:error, :delete_timeout}
    end
  end

  defp coordinator! do
    :storyarn
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:coordinator)
  end
end
