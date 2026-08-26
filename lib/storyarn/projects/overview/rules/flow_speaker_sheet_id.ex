defmodule Storyarn.Projects.FlowSpeakerSheetId do
  @moduledoc false

  @doc false
  defmacro safe_query_value(data) do
    quote do
      fragment(
        """
        CASE
          WHEN (?->>'speaker_sheet_id') ~ '^[0-9]+$'
            AND (
              char_length(ltrim(?->>'speaker_sheet_id', '0')) < 19
              OR (
                char_length(ltrim(?->>'speaker_sheet_id', '0')) = 19
                AND ltrim(?->>'speaker_sheet_id', '0') <= '9223372036854775807'
              )
            )
          THEN coalesce(nullif(ltrim(?->>'speaker_sheet_id', '0'), ''), '0')::bigint
          ELSE NULL
        END
        """,
        unquote(data),
        unquote(data),
        unquote(data),
        unquote(data),
        unquote(data)
      )
    end
  end
end
