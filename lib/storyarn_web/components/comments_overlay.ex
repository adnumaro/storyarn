defmodule StoryarnWeb.Components.CommentsOverlay do
  @moduledoc "Mounts conversation review independently of the surrounding page."
  use StoryarnWeb, :html

  attr :socket, :any, required: true
  attr :current_scope, :map, required: true
  attr :project_id, :integer, default: nil
  attr :workspace_id, :integer, default: nil

  def overlay(assigns) do
    ~H"""
    {live_render(@socket, StoryarnWeb.CommentLive.Overlay,
      id: "comments-overlay",
      session: %{
        "current_scope" => @current_scope,
        "project_id" => @project_id,
        "workspace_id" => @workspace_id,
        "locale" => Gettext.get_locale(Storyarn.Gettext)
      }
    )}
    """
  end
end
