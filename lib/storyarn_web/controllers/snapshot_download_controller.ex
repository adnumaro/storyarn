defmodule StoryarnWeb.SnapshotDownloadController do
  @moduledoc false

  use StoryarnWeb, :controller

  @doc """
  Fails closed until ENG-83 implements an authorized export of the canonical
  object set. Canonical storage is never exposed as the old gzip archive.
  """
  def download(conn, _params) do
    conn
    |> put_status(:not_found)
    |> text(gettext("Snapshot download is not available"))
  end
end
