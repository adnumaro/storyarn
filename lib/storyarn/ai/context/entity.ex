defmodule Storyarn.AI.Context.Entity do
  @moduledoc false

  alias Storyarn.Shared.CanonicalJSON

  @enforce_keys [:type, :id, :content, :required?, :priority, :revision, :hash, :serialized_bytes]
  defstruct [:type, :id, :content, :required?, :priority, :revision, :hash, :serialized_bytes]

  @type t :: %__MODULE__{}

  @spec new(String.t(), integer() | String.t(), map(), keyword()) ::
          {:ok, t()} | {:error, :context_serialization_failed}
  def new(type, id, content, opts \\ [])

  def new(type, id, content, opts) when is_binary(type) and (is_integer(id) or is_binary(id)) and is_map(content) do
    with {:ok, encoded} <- CanonicalJSON.encode(content),
         {:ok, hash} <- CanonicalJSON.hash(content) do
      {:ok,
       %__MODULE__{
         type: type,
         id: id,
         content: content,
         required?: Keyword.get(opts, :required, false),
         priority: Keyword.get(opts, :priority, 4),
         revision: normalize_revision(Keyword.get(opts, :revision), hash),
         hash: hash,
         serialized_bytes: byte_size(encoded)
       }}
    else
      {:error, _reason} -> {:error, :context_serialization_failed}
    end
  end

  def new(_type, _id, _content, _opts), do: {:error, :context_serialization_failed}

  @spec payload(t()) :: map()
  def payload(%__MODULE__{} = entity) do
    %{
      "type" => entity.type,
      "id" => entity.id,
      "content" => entity.content
    }
  end

  @spec manifest(t()) :: map()
  def manifest(%__MODULE__{} = entity) do
    %{
      "type" => entity.type,
      "id" => entity.id,
      "required" => entity.required?,
      "priority" => entity.priority,
      "revision" => entity.revision,
      "hash" => entity.hash,
      "serialized_bytes" => entity.serialized_bytes
    }
  end

  defp normalize_revision(nil, hash), do: "sha256:" <> hash
  defp normalize_revision(%DateTime{} = value, _hash), do: DateTime.to_iso8601(value)
  defp normalize_revision(%NaiveDateTime{} = value, _hash), do: NaiveDateTime.to_iso8601(value)
  defp normalize_revision(value, _hash) when is_binary(value), do: value
  defp normalize_revision(_value, hash), do: "sha256:" <> hash
end
