defmodule Storyarn.Ideation.Ideas.Rules.Input do
  @moduledoc false
  alias Storyarn.Platform.Kernel.MapAccess

  defguard valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807
  defguard valid_revision(number) when is_integer(number) and number > 0 and number <= 2_147_483_647

  def get(attrs, key), do: MapAccess.get_flexible(attrs, key)

  def request_key(attrs) when is_map(attrs) do
    case Ecto.UUID.cast(get(attrs, :request_key)) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :invalid_request_key}
    end
  end

  def request_key(_), do: {:error, :invalid_request_key}

  def fingerprint(term), do: :crypto.hash(:sha256, :erlang.term_to_binary({:ideation_edit_v1, term}))

  def content_attrs(attrs) do
    for field <- [:title, :body, :state],
        Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field)),
        into: %{},
        do: {field, get(attrs, field)}
  end

  def page(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      limit = Keyword.get(opts, :limit, 50)
      before_id = Keyword.get(opts, :before_id)

      if is_integer(limit) and limit in 1..200 and (is_nil(before_id) or valid_id(before_id)),
        do: {:ok, limit, before_id},
        else: {:error, :invalid_options}
    else
      {:error, :invalid_options}
    end
  end

  def page(_), do: {:error, :invalid_options}
end
