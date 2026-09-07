defmodule Storyarn.Ideation.Sessions.Queries.Page do
  @moduledoc false

  def options(opts) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    if is_integer(limit) and limit in 1..200 and
         (is_nil(before_id) or (is_integer(before_id) and before_id > 0)),
       do: {:ok, limit, before_id},
       else: {:error, :invalid_options}
  end
end
