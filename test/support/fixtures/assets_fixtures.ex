defmodule Storyarn.AssetsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Storyarn.Assets` context.
  """

  alias Storyarn.Assets

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

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
    attrs = valid_asset_attributes(attrs)

    {:ok, asset} = Assets.create_asset(project, user, attrs)
    asset
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
end
