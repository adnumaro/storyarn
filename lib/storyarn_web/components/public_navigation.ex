defmodule StoryarnWeb.Components.PublicNavigation do
  @moduledoc false

  use StoryarnWeb, :html

  attr :landing, :boolean, required: true
  attr :home_url, :string, required: true
  attr :section, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def section_link(assigns) do
    assigns = assign(assigns, :target, "#{assigns.home_url}##{assigns.section}")

    ~H"""
    <%= if @landing do %>
      <a href={"##{@section}"} class={@class} {@rest}>
        {render_slot(@inner_block)}
      </a>
    <% else %>
      <.link navigate={@target} class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
    <% end %>
    """
  end
end
