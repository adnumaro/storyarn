defmodule Storyarn.Scenes.Editor.Queries.Preloads do
  @moduledoc false

  alias Storyarn.Repo

  def preload_pin_associations(pin) do
    Repo.preload(pin, [:icon_asset, sheet: [avatars: :asset]], force: true)
  end

  def preload_scene_background(scene) do
    Repo.preload(scene, :background_asset, force: true)
  end

  def preload_sheet_avatar(sheet) do
    Repo.preload(sheet, avatars: :asset)
  end
end
