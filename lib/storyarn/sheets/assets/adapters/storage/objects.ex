defmodule Storyarn.Sheets.Assets.Adapters.Storage.Objects do
  @moduledoc false

  alias Storyarn.Projects.Assets.Storage

  defdelegate get_url(key), to: Storage
  defdelegate put_if_absent(key, data, content_type), to: Storage
  defdelegate copy_if_absent(source_key, destination_key), to: Storage
  defdelegate canonical_key?(key), to: Storage
  defdelegate stat(key), to: Storage
  defdelegate stream(key, offset, length, opts \\ []), to: Storage

  def delete_if_matches(key, expected_identity) do
    Storage.adapter().delete_if_matches(key, expected_identity)
  end
end
