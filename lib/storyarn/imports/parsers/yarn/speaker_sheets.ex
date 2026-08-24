defmodule Storyarn.Imports.Parsers.Yarn.SpeakerSheets do
  @moduledoc false

  alias Storyarn.Imports.Parsers.Yarn.Shortcut
  alias Storyarn.Projects.NameNormalizer

  @description "Imported Yarn Spinner character"
  @color "#8b5cf6"

  @doc false
  @spec append([map()], [String.t()]) :: {[map()], %{optional(String.t()) => String.t()}}
  def append(retained_sheets, speakers) when is_list(retained_sheets) and is_list(speakers) do
    used_shortcuts =
      retained_sheets
      |> Enum.map(&Map.get(&1, "shortcut"))
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    {speaker_sheets, speaker_ids, _used_shortcuts} =
      speakers
      |> Enum.with_index(length(retained_sheets))
      |> Enum.reduce({[], %{}, used_shortcuts}, fn {speaker, position}, {built, ids, used} ->
        shortcut = speaker |> NameNormalizer.shortcutify() |> Shortcut.unique(used)
        id = id(speaker)

        sheet = %{
          "id" => id,
          "name" => speaker,
          "shortcut" => shortcut,
          "description" => @description,
          "color" => @color,
          "position" => position,
          "blocks" => []
        }

        {[sheet | built], Map.put(ids, speaker, id), MapSet.put(used, shortcut)}
      end)

    {retained_sheets ++ Enum.reverse(speaker_sheets), speaker_ids}
  end

  @doc false
  @spec id(String.t()) :: String.t()
  def id(speaker) when is_binary(speaker), do: "speaker_sheet_#{digest(speaker)}"

  defp digest(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end
end
