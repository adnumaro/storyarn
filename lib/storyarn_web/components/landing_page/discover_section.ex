defmodule StoryarnWeb.Components.LandingPage.DiscoverSection do
  @moduledoc """
  Discover section for the landing page.
  3D monitor backdrop with text overlays per feature tab.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.TextComponents, only: [widont: 1]

  def discover_section(assigns) do
    features = discover_features()
    active_feature = features |> hd() |> Map.fetch!(:id)
    active_slide = features |> hd() |> Map.fetch!(:slides) |> hd() |> Map.fetch!(:id)

    assigns =
      assigns
      |> assign(:features, features)
      |> assign(:active_feature, active_feature)
      |> assign(:active_slide, active_slide)

    ~H"""
    <section class="lp-auto-section lp-discover-section" id="discover" data-section-step>
      <div
        class="lp-discover-stage"
        data-feature-shell
        data-active-feature={@active_feature}
        data-active-slide={@active_slide}
      >
        <%!-- 3D monitor canvas backdrop --%>
        <div class="lp-discover-canvas-wrap">
          <canvas id="discover-monitor-canvas"></canvas>
        </div>

        <%!-- Text overlays (one per sub-step) --%>
        <.discover_text
          :for={{feature, index} <- Enum.with_index(@features)}
          feature={feature}
          slide={hd(feature.slides)}
          index={index}
          active_feature={@active_feature}
        />

        <%!-- Tab indicators --%>
        <div class="lp-discover-indicators">
          <button
            :for={feature <- @features}
            class={["lp-discover-tab", feature.id == @active_feature && "is-active"]}
            type="button"
            role="tab"
            aria-selected={if(feature.id == @active_feature, do: "true", else: "false")}
            data-feature-tab={feature.id}
          >
            {feature.label}
          </button>
        </div>

        <%!-- Hidden step markers for section_scroll.js flat-step mapping --%>
        <div class="hidden">
          <%= for feature <- @features do %>
            <%= for slide <- feature.slides do %>
              <span data-feature-step={feature.id} data-slide={slide.id}></span>
            <% end %>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  attr :feature, :map, required: true
  attr :slide, :map, required: true
  attr :index, :integer, required: true
  attr :active_feature, :string, required: true

  defp discover_text(assigns) do
    ~H"""
    <div
      class={[
        "lp-discover-text",
        @feature.id == @active_feature && "is-active"
      ]}
      data-discover-text={@index}
      data-feature-tab={@feature.id}
    >
      <span class="lp-discover-text-kicker">
        {@feature.label}
      </span>
      <h3 class="lp-discover-text-title">
        {widont(@slide.title)}
      </h3>
      <p class="lp-discover-text-desc">
        {widont(@slide.description)}
      </p>
      <ul class="lp-discover-text-points">
        <li :for={item <- @slide.items}>{widont(item)}</li>
      </ul>
    </div>
    """
  end

  defp discover_features do
    [
      %{
        id: "sheets",
        label: gettext("Sheets"),
        slides: [
          %{
            id: "sheets-inheritance",
            trigger: gettext("Inheritance"),
            title: gettext("Inheritance keeps your world consistent"),
            description:
              gettext(
                "Parent and child sheets let you evolve characters, factions, and locations without duplicating structures."
              ),
            items: [
              gettext("Shared variables and blocks flow down the hierarchy."),
              gettext("Override only what changes — per variant, episode, or region."),
              gettext("Scale the world model without copy-paste.")
            ]
          }
        ]
      },
      %{
        id: "flows",
        label: gettext("Flows"),
        slides: [
          %{
            id: "flows-node-graph",
            trigger: gettext("Node graph"),
            title: gettext("Visual graphs that stay readable as scope grows"),
            description:
              gettext(
                "Dialogue, conditions, instructions, and branches in one graph — designed to stay clear even at production scale."
              ),
            items: [
              gettext("Conversations, state changes, and exits — modeled in one surface."),
              gettext("Logic stays connected to project data instead of living in fragments."),
              gettext("From quick sketches to production-scale dialogue graphs.")
            ]
          }
        ]
      },
      %{
        id: "scenes",
        label: gettext("Scenes"),
        slides: [
          %{
            id: "scenes-layers",
            trigger: gettext("Layers"),
            title: gettext("Layers and fog keep complex maps readable"),
            description:
              gettext(
                "Layers let you stage progression, visibility, and structure without flattening everything into one image."
              ),
            items: [
              gettext("Layered visibility instead of one overloaded canvas."),
              gettext("Fog of war to communicate progression and discoverability."),
              gettext("Large spaces stay understandable during review and iteration.")
            ]
          }
        ]
      }
    ]
  end
end
