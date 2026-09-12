defmodule Storyarn.Ideation.References.ContextualInput do
  @moduledoc false
  import Storyarn.Ideation.References.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.References.Input

  @types ~w(sheet flow scene)

  def target(type, id) when type in @types and valid_id(id), do: :ok
  def target(_, _), do: {:error, :not_found}

  def command(attrs, operation) when is_map(attrs) do
    type = Input.get(attrs, :target_type)
    id = Input.get(attrs, :target_id)
    identity = Input.get(attrs, :target_identity)
    fingerprint = Input.get(attrs, :target_fingerprint)

    with :ok <- target(type, id),
         true <- valid_identity?(identity) and valid_fingerprint?(fingerprint),
         {:ok, key} <- Input.request_key(Input.get(attrs, :request_key)) do
      values = %{
        target_type: type,
        target_id: id,
        target_identity: identity,
        target_fingerprint: fingerprint,
        request_key: key
      }

      session_attrs = Map.new([:title, :objective, :context], &{&1, Input.get(attrs, &1)})
      {:ok, if(operation == :create, do: Map.put(values, :session_attrs, session_attrs), else: values)}
    else
      {:error, :invalid_request_key} = error -> error
      _ -> {:error, :invalid_context}
    end
  end

  def command(_, _), do: {:error, :invalid_context}

  def page(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      limit = Keyword.get(opts, :limit, 20)
      linked = opts[:linked_before_id]
      available = opts[:available_before_id]
      search = Keyword.get(opts, :search, "")

      if is_integer(limit) and limit in 1..50 and optional_id?(linked) and optional_id?(available) and
           is_binary(search) and byte_size(search) <= 500 do
        {:ok, %{limit: limit, linked_before_id: linked, available_before_id: available, search: String.trim(search)}}
      else
        {:error, :invalid_pagination}
      end
    else
      {:error, :invalid_pagination}
    end
  end

  def page(_), do: {:error, :invalid_pagination}

  def fingerprint(attrs, operation, session_id) do
    attrs = Map.delete(attrs, :request_key)
    :crypto.hash(:sha256, :erlang.term_to_binary({:contextual_brainstorming_v1, operation, session_id, attrs}))
  end

  defp optional_id?(nil), do: true
  defp optional_id?(id), do: valid_id(id)
  defp valid_identity?("created:" <> timestamp), do: match?({:ok, _, _}, DateTime.from_iso8601(timestamp))
  defp valid_identity?(_), do: false
  defp valid_fingerprint?(value) when is_binary(value), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp valid_fingerprint?(_), do: false
end
