defmodule StoryarnWeb.Components.LandingPage.DiscoverSection do
  @moduledoc """
  Discover section (tabbed interactive) for the landing page.
  """
  use StoryarnWeb, :html

  def discover_section(assigns) do
    ~H"""
    <section class="py-16 lg:py-20" id="discover">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("Discover the product pillars")}
          description={
            gettext(
              "This section summarizes the main tools in Storyarn. Understand the platform architecture at a glance: global vision, structured modeling, visual authoring and scenes."
            )
          }
        />

        <div class="lp-discover-scrollbox" data-feature-scrollbox>
          <div class="lp-discover-shell" data-feature-shell data-active-feature="dashboard">
            <div class="lp-discover-stage">
              <div class="p-4 rounded-[2rem] border border-base-content/8 bg-base-200/60">
                <.discover_tabs />
                <div class="lp-discover-display">
                  <.discover_preview_dashboard />
                  <.discover_preview_sheets />
                  <.discover_preview_flows />
                  <.discover_preview_scenes />
                </div>
              </div>
            </div>

            <div class="lp-discover-steps">
              <.discover_step
                feature="dashboard"
                number={gettext("Feature 01")}
                title={gettext("Dashboards")}
                description={
                  gettext(
                    "Project-level dashboards make the platform readable at a glance: scale, content health, warnings, localization progress and shipping readiness."
                  )
                }
                items={[
                  gettext("One place to understand the narrative state of the whole project."),
                  gettext("Turns Storyarn into a platform, not a collection of isolated editors."),
                  gettext("Ideal for producers, leads and cross-discipline reviews.")
                ]}
                active
              />
              <.discover_step
                feature="sheets"
                number={gettext("Feature 02")}
                title={gettext("Sheets")}
                description={
                  gettext(
                    "Worldbuilding becomes data instead of scattered notes. Every entity lives in a reusable structure with depth and internal logic."
                  )
                }
                items={[
                  gettext("Characters, locations, factions, quests and items in one system."),
                  gettext("Variables, blocks and inheritance make narrative rules editable."),
                  gettext("Each sheet can open as a full surface, not just a row in a table.")
                ]}
              />
              <.discover_step
                feature="flows"
                number={gettext("Feature 03")}
                title={gettext("Flows")}
                description={
                  gettext(
                    "A visual authoring surface for dialogue trees, checks, branches and consequences with a workflow that feels familiar to narrative teams."
                  )
                }
                items={[
                  gettext("Clear graph editing for dialogue, conditions, instructions and exits."),
                  gettext(
                    "Nodes pull from live project data instead of disconnected text fragments."
                  ),
                  gettext("Strong fit for teams coming from articy:draft or Arcweaver.")
                ]}
              />
              <.discover_step
                feature="scenes"
                number={gettext("Feature 04")}
                title={gettext("Scenes")}
                description={
                  gettext(
                    "Scene tools help teams think spatially before engineering: layers, zones, pins and map surfaces turn environments into usable design assets."
                  )
                }
                items={[
                  gettext("Readable scene dashboards before moving into interactive layers."),
                  gettext("Spatial structure for narrative beats, triggers and world readability."),
                  gettext("A clear bridge between pure writing and playable presentation.")
                ]}
              />
              <div class="lp-discover-spacer" aria-hidden="true"></div>
              <div class="lp-discover-spacer" aria-hidden="true"></div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true

  defp section_header(assigns) do
    ~H"""
    <div class="flex flex-col lg:flex-row items-start lg:items-end justify-between gap-7 mb-8">
      <h2 class="text-[clamp(2.2rem,3vw,3.8rem)] leading-[0.97] tracking-[-0.06em] font-bold max-w-[12ch] text-base-content">
        {@title}
      </h2>
      <p class="max-w-[36rem] text-base-content/60 leading-relaxed text-base">{@description}</p>
    </div>
    """
  end

  defp discover_tabs(assigns) do
    ~H"""
    <div class="lp-discover-tabs" role="tablist" aria-label={gettext("Main features")}>
      <button class="lp-discover-tab" type="button" role="tab" data-feature="dashboard">
        {gettext("Dashboards")}
      </button>
      <button class="lp-discover-tab" type="button" role="tab" data-feature="sheets">
        {gettext("Sheets")}
      </button>
      <button class="lp-discover-tab" type="button" role="tab" data-feature="flows">
        {gettext("Flows")}
      </button>
      <button class="lp-discover-tab" type="button" role="tab" data-feature="scenes">
        {gettext("Scenes")}
      </button>
    </div>
    """
  end

  attr :feature, :string, required: true
  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :items, :list, required: true
  attr :active, :boolean, default: false

  defp discover_step(assigns) do
    ~H"""
    <article class={["lp-discover-step", @active && "is-active"]} data-feature-step={@feature}>
      <strong class="block mb-2 text-base-content/70 text-xs tracking-widest uppercase">
        {@number}
      </strong>
      <h3 class="mb-3.5 text-2xl tracking-tight font-bold text-base-content">{@title}</h3>
      <p class="text-base-content/60 leading-relaxed">{@description}</p>
      <ul class="mt-4 grid gap-2.5 list-none p-0">
        <li :for={item <- @items} class="lp-step-item">{item}</li>
      </ul>
    </article>
    """
  end

  defp discover_preview_dashboard(assigns) do
    ~H"""
    <section class="lp-discover-preview" data-feature="dashboard">
      <.discover_preview_head
        title={gettext("Project dashboards that frame the whole narrative system")}
        subtitle={
          gettext(
            "Storyarn starts at project level: key metrics, warnings, coverage, exports and status across the full production pipeline."
          )
        }
        badge={gettext("Project overview")}
      />
      <div class="lp-preview-card">
        <div class="lp-preview-info">
          <strong class="block mb-2 text-base text-base-content">
            {gettext("Harbor of Broken Oaths")}
          </strong>
          <p class="text-base-content/60 text-sm leading-relaxed">
            {gettext(
              "A cross-tool dashboard that helps teams track narrative scale, content health and production readiness from one place."
            )}
          </p>
          <ul class="mt-3 pl-4 text-base-content/70 text-xs leading-relaxed list-disc">
            <li>{gettext("126 connected variables across sheets, flows and scenes")}</li>
            <li class="mt-1.5">{gettext("91 branching flows active in the current project")}</li>
            <li class="mt-1.5">{gettext("81% localization coverage ready for review")}</li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  defp discover_preview_sheets(assigns) do
    ~H"""
    <section class="lp-discover-preview" data-feature="sheets">
      <.discover_preview_head
        title={gettext("Sheets organize the world as structured, reusable data")}
        subtitle={
          gettext(
            "Characters, factions, locations and item logic live in a connected system with variables, blocks and inheritance."
          )
        }
        badge={gettext("Structured worldbuilding")}
      />
      <div class="lp-preview-card" style="align-items: center; justify-content: center;">
        <div class="lp-preview-info" style="max-width: 400px;">
          <strong class="block mb-2 text-base text-base-content">
            {gettext("Characters, stats, and inheritance")}
          </strong>
          <p class="text-base-content/60 text-sm leading-relaxed">
            {gettext(
              "Every entity in a sheet carries variables, blocks and formulas. Child sheets inherit from parents, keeping your world consistent."
            )}
          </p>
          <ul class="mt-3 pl-4 text-base-content/70 text-xs leading-relaxed list-disc">
            <li>{gettext("Characters, locations, factions, quests and items in one system")}</li>
            <li class="mt-1.5">
              {gettext("Variables, blocks and inheritance make narrative rules editable")}
            </li>
            <li class="mt-1.5">
              {gettext("Each sheet can open as a full surface, not just a row in a table")}
            </li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  defp discover_preview_flows(assigns) do
    ~H"""
    <section class="lp-discover-preview" data-feature="flows">
      <.discover_preview_head
        title={gettext("Flows turn branching narrative into an editable graph")}
        subtitle={
          gettext(
            "Familiar to anyone coming from articy:draft or Arcweaver, but wired directly into sheets, scenes, drafts and export."
          )
        }
        badge={gettext("Visual narrative logic")}
      />
      <div class="lp-preview-card" style="align-items: center; justify-content: center;">
        <div class="lp-preview-info" style="max-width: 400px;">
          <strong class="block mb-2 text-base text-base-content">
            {gettext("Narrative graph with live data hooks")}
          </strong>
          <p class="text-base-content/60 text-sm leading-relaxed">
            {gettext(
              "A visual authoring surface for dialogue trees, checks, branches and consequences with a workflow that feels familiar to narrative teams."
            )}
          </p>
          <ul class="mt-3 pl-4 text-base-content/70 text-xs leading-relaxed list-disc">
            <li>
              {gettext("Clear graph editing for dialogue, conditions, instructions and exits")}
            </li>
            <li class="mt-1.5">
              {gettext("Nodes pull from live project data instead of disconnected text fragments")}
            </li>
            <li class="mt-1.5">
              {gettext("Strong fit for teams coming from articy:draft or Arcweaver")}
            </li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  defp discover_preview_scenes(assigns) do
    ~H"""
    <section class="lp-discover-preview" data-feature="scenes">
      <.discover_preview_head
        title={gettext("Scenes give the world spatial structure before implementation")}
        subtitle={
          gettext(
            "Layered maps, zones and pins make scenes readable as systems, not as loose concept art or disconnected layout files."
          )
        }
        badge={gettext("Spatial narrative layout")}
      />
      <div class="lp-preview-card" style="align-items: center; justify-content: center;">
        <div class="lp-preview-info" style="max-width: 400px;">
          <strong class="block mb-2 text-base text-base-content">
            {gettext("Spatial structure for narrative beats")}
          </strong>
          <p class="text-base-content/60 text-sm leading-relaxed">
            {gettext(
              "Scene tools help teams think spatially before engineering: layers, zones, pins and map surfaces turn environments into usable design assets."
            )}
          </p>
          <ul class="mt-3 pl-4 text-base-content/70 text-xs leading-relaxed list-disc">
            <li>
              {gettext("Readable scene dashboards before moving into interactive layers")}
            </li>
            <li class="mt-1.5">
              {gettext("Spatial structure for narrative beats, triggers and world readability")}
            </li>
            <li class="mt-1.5">
              {gettext("A clear bridge between pure writing and playable presentation")}
            </li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :badge, :string, required: true

  defp discover_preview_head(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row items-start justify-between gap-4 mb-5">
      <div>
        <strong class="block text-xl tracking-tight text-base-content">{@title}</strong>
        <span class="block mt-1.5 text-base-content/50 text-sm leading-relaxed">{@subtitle}</span>
      </div>
      <span class="badge badge-ghost badge-sm whitespace-nowrap">{@badge}</span>
    </div>
    """
  end
end
