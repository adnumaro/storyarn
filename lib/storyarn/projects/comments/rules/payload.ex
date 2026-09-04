defmodule Storyarn.Projects.Comments.Payload do
  @moduledoc false

  def normalize(attrs) when is_map(attrs) do
    body = value(attrs, :body)
    request_id = value(attrs, :client_request_id)
    mentions = value(attrs, :mention_user_ids) || []

    with true <- valid_text?(body, 40_000),
         body = String.trim(body),
         true <- length(String.codepoints(body)) in 1..10_000,
         true <- valid_text?(request_id, 64),
         true <- is_list(mentions) and length(mentions) <= 50,
         true <- Enum.all?(mentions, &valid_id?/1) do
      {:ok, %{body: body, client_request_id: request_id, mention_user_ids: Enum.sort(Enum.uniq(mentions))}}
    else
      _ -> {:error, :invalid_comment}
    end
  end

  def normalize(_), do: {:error, :invalid_comment}

  def fingerprint(payload, target) do
    {target, payload.body, payload.mention_user_ids}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  def valid_id?(id), do: is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  defp valid_text?(text, max_bytes) do
    is_binary(text) and byte_size(text) in 1..max_bytes and String.valid?(text) and not String.contains?(text, <<0>>)
  end
end
