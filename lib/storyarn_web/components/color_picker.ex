defmodule StoryarnWeb.Components.ColorPicker do
  @moduledoc """
  Renders a full-spectrum color picker using vanilla-colorful.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :color, :string, default: "#8b5cf6"
  attr :event, :string, required: true
  attr :field, :string, default: "color"
  attr :disabled, :boolean, default: false

  def color_picker(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="ColorPicker"
      phx-update="ignore"
      data-color={@color || "#8b5cf6"}
      data-event={@event}
      data-field={@field}
      class={[@disabled && "pointer-events-none opacity-50"]}
    />
    """
  end
end
