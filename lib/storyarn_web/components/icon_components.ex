defmodule StoryarnWeb.Components.IconComponents do
  @moduledoc """
  Small server-rendered Lucide icon component for HEEx surfaces.

  Vue surfaces continue to use `lucide-vue-next`; this component keeps native
  LiveView markup on the same icon system without client-side JavaScript.
  """

  use Phoenix.Component

  @icons %{
    "arrow-left" => ["m12 19-7-7 7-7", "M19 12H5"],
    "arrow-right" => ["M5 12h14", "m12 5 7 7-7 7"],
    "book-open" => [
      "M12 7v14",
      "M3 18a1 1 0 0 1-1-1V5a2 2 0 0 1 2-2h5a3 3 0 0 1 3 3v15a3 3 0 0 0-3-3Z",
      "M21 18a1 1 0 0 0 1-1V5a2 2 0 0 0-2-2h-5a3 3 0 0 0-3 3v15a3 3 0 0 1 3-3Z"
    ],
    "check" => ["M20 6 9 17l-5-5"],
    "chevron-down" => ["m6 9 6 6 6-6"],
    "mail" => [
      "m22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7",
      "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"
    ],
    "menu" => ["M4 12h16", "M4 6h16", "M4 18h16"],
    "newspaper" => [
      "M15 18h-5",
      "M18 14h-8",
      "M2 8h20",
      "M18 6h-8",
      "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z",
      "M6 14h.01",
      "M6 18h.01"
    ],
    "panels-top-left" => ["M3 3h18v18H3z", "M3 9h18", "M9 21V9"],
    "sparkles" => [
      "M9.937 15.5A2 2 0 0 0 8.5 14.063l-.4-1.1a2 2 0 0 0-1.2-1.2l-1.1-.4a2 2 0 0 0 0-3.726l1.1-.4a2 2 0 0 0 1.2-1.2l.4-1.1a2 2 0 0 0 3.726 0l.4 1.1a2 2 0 0 0 1.2 1.2l1.1.4a2 2 0 0 0 0 3.726l-1.1.4a2 2 0 0 0-1.2 1.2l-.4 1.1a2 2 0 0 0-2.289 1.437Z",
      "M20 3v4",
      "M22 5h-4",
      "M4 17v2",
      "M5 18H3"
    ],
    "x" => ["M18 6 6 18", "m6 6 12 12"]
  }

  attr :name, :string, required: true
  attr :class, :string, default: "size-4"
  attr :rest, :global

  def icon(assigns) do
    assigns = assign(assigns, :paths, Map.fetch!(@icons, assigns.name))

    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {@rest}
    >
      <path :for={path <- @paths} d={path} />
    </svg>
    """
  end
end
