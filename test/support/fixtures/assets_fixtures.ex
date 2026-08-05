defmodule Storyarn.AssetsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Storyarn.Assets` context.
  """

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets

  @max_asset_size 50 * 1024 * 1024

  def valid_asset_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      filename: "test_image_#{System.unique_integer([:positive])}.jpg",
      content_type: "image/jpeg",
      size: 12_345,
      key: "projects/test/assets/#{Ecto.UUID.generate()}.jpg",
      url: "/uploads/projects/test/assets/test.jpg",
      metadata: %{}
    })
  end

  def asset_fixture(project \\ nil, user \\ nil, attrs \\ %{}) do
    project = project || project_fixture()
    user = user || user_fixture()

    attrs =
      attrs
      |> valid_asset_attributes()
      |> maybe_put_canonical_asset_key(project, attrs)

    {:ok, asset} = Assets.create_asset(project, user, attrs)
    asset
  end

  defp maybe_put_canonical_asset_key(attrs, project, supplied_attrs) do
    if Map.has_key?(supplied_attrs, :key) or Map.has_key?(supplied_attrs, "key") do
      attrs
    else
      filename = Map.get(attrs, :filename, Map.get(attrs, "filename"))
      Map.put(attrs, :key, Assets.generate_key(project, filename))
    end
  end

  def image_asset_fixture(project \\ nil, user \\ nil, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          content_type: "image/png",
          metadata: %{"width" => 800, "height" => 600}
        },
        attrs
      )

    asset_fixture(project, user, attrs)
  end

  def audio_asset_fixture(project \\ nil, user \\ nil, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          filename: "test_audio_#{System.unique_integer([:positive])}.mp3",
          content_type: "audio/mpeg",
          metadata: %{"duration" => 180}
        },
        attrs
      )

    asset_fixture(project, user, attrs)
  end

  def fill_storage_fixture(project, user, total_bytes) when is_integer(total_bytes) and total_bytes >= 0 do
    fill_storage_fixture(project, user, total_bytes, [])
  end

  defp fill_storage_fixture(_project, _user, 0, assets), do: Enum.reverse(assets)

  defp fill_storage_fixture(project, user, remaining_bytes, assets) do
    asset_size = min(remaining_bytes, @max_asset_size)
    asset = image_asset_fixture(project, user, %{size: asset_size})
    fill_storage_fixture(project, user, remaining_bytes - asset_size, [asset | assets])
  end
end
