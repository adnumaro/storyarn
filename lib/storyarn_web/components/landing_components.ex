defmodule StoryarnWeb.Components.LandingComponents do
  @moduledoc """
  Function components for the public landing page.
  Each section of the landing page is a separate component.
  """
  use StoryarnWeb, :html

  # ──────────────────────────────────────────────
  # Hero
  # ──────────────────────────────────────────────

  def hero(assigns) do
    ~H"""
    <section class="relative overflow-hidden pt-12 pb-8 lg:pt-16 lg:pb-12">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="relative min-h-[1180px] lg:min-h-[1100px]">
          <div class="relative z-3 w-full max-w-[1100px] pt-12 lg:pt-20">
            <%!-- Eyebrow badge --%>
            <div class="inline-flex items-center gap-2.5 px-4 py-2.5 rounded-full border border-primary/20 bg-primary/10 text-primary text-xs tracking-widest uppercase">
              <span class="w-2.5 h-2.5 rounded-full bg-primary shadow-[0_0_20px_var(--color-primary)]">
              </span>
              {gettext("Private beta for studios and narrative teams")}
            </div>

            <%!-- Masthead: mascot + title --%>
            <div class="flex items-start gap-7 mt-7">
              <img
                class="w-52 flex-none mt-10 drop-shadow-2xl hidden sm:block"
                src={~p"/images/logo-dark-200.png"}
                alt=""
              />
              <div>
                <h1 class="text-[clamp(4rem,7.2vw,7.2rem)] leading-[0.88] tracking-[-0.07em] font-bold text-base-content">
                  {gettext("Craft worlds.")}
                  <span class="block mt-1.5 brand-logotype text-[1em]">
                    {gettext("Weave stories.")}
                  </span>
                </h1>
              </div>
            </div>

            <p class="mt-6 max-w-[46rem] text-base-content/60 text-lg leading-relaxed">
              {gettext(
                "Storyarn brings sheets, flows, scenes, screenplays, and localization into a single platform for interactive narrative. Everything connected: characters, variables, branches, maps, and export for your engine."
              )}
            </p>

            <.hero_pills />

            <div class="flex flex-wrap gap-3.5 mt-8">
              <a href="#product" class="btn btn-primary btn-lg rounded-full">
                {gettext("Explore Storyarn")}
              </a>
              <a
                href="#workflow"
                class="btn btn-ghost btn-lg rounded-full border border-base-content/10"
              >
                {gettext("See workflow")}
              </a>
            </div>
          </div>

          <.product_window />
        </div>
      </div>
    </section>
    """
  end

  defp hero_pills(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-3 mt-7">
      <span class="px-3.5 py-2.5 rounded-full border border-base-content/10 bg-base-content/5 text-base-content/70 text-sm">
        {gettext("Sheets with inheritable variables")}
      </span>
      <span class="px-3.5 py-2.5 rounded-full border border-base-content/10 bg-base-content/5 text-base-content/70 text-sm">
        {gettext("Flows with debug and story player")}
      </span>
      <span class="px-3.5 py-2.5 rounded-full border border-base-content/10 bg-base-content/5 text-base-content/70 text-sm">
        {gettext("Explorable scenes")}
      </span>
      <span class="px-3.5 py-2.5 rounded-full border border-base-content/10 bg-base-content/5 text-base-content/70 text-sm">
        {gettext("Integrated localization and export")}
      </span>
    </div>
    """
  end

  # ──────────────────────────────────────────────
  # Product Window (decorative app simulation)
  # ──────────────────────────────────────────────

  defp product_window(assigns) do
    ~H"""
    <section class="lp-hero-product" id="product">
      <div class="rounded-[2rem] border border-base-content/8 bg-base-200/90 shadow-2xl overflow-hidden">
        <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 p-5 border-b border-base-content/7">
          <div>
            <strong class="block text-base tracking-tight text-base-content">
              {gettext("Project: Harbor of Broken Oaths")}
            </strong>
            <span class="block mt-1 text-base-content/50 text-xs">
              {gettext("Narrative RPG - 4 languages - 12 active scenes - 91 flows")}
            </span>
          </div>
          <div class="flex gap-2.5 flex-wrap">
            <span class="badge badge-ghost badge-sm">{gettext("Realtime collaboration")}</span>
            <span class="badge badge-ghost badge-sm">{gettext("Version snapshots")}</span>
            <span class="badge badge-ghost badge-sm">{gettext("Debug mode")}</span>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-[210px_1fr] min-h-[760px]">
          <.product_sidebar />
          <.product_workspace />
        </div>
      </div>
    </section>
    """
  end

  defp product_sidebar(assigns) do
    ~H"""
    <aside class="p-4 border-b lg:border-b-0 lg:border-r border-base-content/6 bg-base-content/3">
      <div class="flex items-center gap-3 px-2.5 pb-4">
        <img src={~p"/images/logo-dark-64.png"} alt="" class="w-10 h-10" />
        <div>
          <strong class="block text-sm text-base-content">Storyarn</strong>
          <span class="block mt-1 text-base-content/50 text-xs">
            {gettext("Open narrative design tool")}
          </span>
        </div>
      </div>

      <nav class="grid gap-2">
        <.sidebar_item label={gettext("Dashboard")} />
        <.sidebar_item label={gettext("Sheets")} active />
        <.sidebar_item label={gettext("Flows")} active />
        <.sidebar_item label={gettext("Scenes")} />
        <.sidebar_item label={gettext("Screenplays")} />
        <.sidebar_item label={gettext("Localization")} />
        <.sidebar_item label={gettext("Exports")} />
      </nav>

      <div class="mt-4 p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3">
        <strong class="block text-sm text-base-content">{gettext("Story Player ready")}</strong>
        <span class="block mt-1.5 text-base-content/50 text-xs leading-relaxed">
          {gettext(
            "Test Act II with variables, checks and scene overlays without leaving the project."
          )}
        </span>
      </div>
    </aside>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp sidebar_item(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 px-3.5 py-3 rounded-2xl border",
      if(@active,
        do: "text-base-content bg-primary/10 border-primary/15",
        else: "text-base-content/70 border-transparent"
      )
    ]}>
      <em class="w-2.5 h-2.5 rounded bg-current opacity-80 not-italic"></em>
      {@label}
    </div>
    """
  end

  defp product_workspace(assigns) do
    ~H"""
    <div class="p-4 grid gap-4">
      <.product_metrics />
      <div class="grid grid-cols-1 lg:grid-cols-[1.08fr_0.92fr] gap-4">
        <.product_flow_panel />
        <.product_sheet_panel />
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-[1fr_0.86fr] gap-4">
        <.product_scene_panel />
        <.product_localization_panel />
      </div>
      <.product_screenplay_panel />
    </div>
    """
  end

  defp product_metrics(assigns) do
    ~H"""
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
      <.metric_card value="126" label={gettext("connected variables across sheets, flows and scenes")} />
      <.metric_card value="91" label={gettext("branching flows in the main project")} />
      <.metric_card value="81%" label={gettext("localization coverage ready for review")} />
      <.metric_card value="4" label={gettext("target runtimes: Yarn, Ink, Unity and Godot")} />
    </div>
    """
  end

  attr :value, :string, required: true
  attr :label, :string, required: true

  defp metric_card(assigns) do
    ~H"""
    <div class="p-4 rounded-2xl border border-base-content/7 bg-base-content/3">
      <strong class="block text-2xl tracking-tight text-base-content">{@value}</strong>
      <span class="block mt-1.5 text-base-content/50 text-xs leading-relaxed">{@label}</span>
    </div>
    """
  end

  defp product_flow_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("Flow editor")}
        subtitle={gettext("Dialogue, checks, instructions and synchronized branches")}
        badge={gettext("Node graph - live")}
      />
      <div class="lp-flow-canvas relative min-h-[294px]">
        <div class="lp-connection c1" style="left: 140px; top: 108px; width: 112px; transform: rotate(18deg);"></div>
        <div class="lp-connection c2" style="left: 325px; top: 118px; width: 108px; transform: rotate(-20deg);"></div>
        <div class="lp-connection c3" style="left: 322px; top: 174px; width: 116px; transform: rotate(24deg);"></div>
        <.flow_node class="n1" type={gettext("Dialogue")} title={gettext("Captain Ilya")} desc={gettext("\"The harbor is still closed. I need a reason to open it.\"")} />
        <.flow_node class="n2" type={gettext("Condition")} title="rep_guardia >= 4" desc={gettext("Unlocks the diplomatic route and updates the harbor gate.")} />
        <.flow_node class="n3" type={gettext("Choice")} title={gettext("Show travel permit")} desc={gettext("Consumes item, adds trust and enters the night harbor scene.")} />
        <.flow_node class="n4" type={gettext("Subflow")} title={gettext("Night Harbor")} desc={gettext("Activates overlay, scene pin and global act state.")} />
      </div>
    </section>
    """
  end

  attr :class, :string, required: true
  attr :type, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, required: true

  defp flow_node(assigns) do
    ~H"""
    <div class={"lp-node #{@class}"}>
      <em>{@type}</em>
      <strong>{@title}</strong>
      <small>{@desc}</small>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :badge, :string, required: true

  defp panel_header(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 p-4 border-b border-base-content/7">
      <div>
        <strong class="block text-base tracking-tight text-base-content">{@title}</strong>
        <span class="text-base-content/50 text-xs">{@subtitle}</span>
      </div>
      <span class="text-base-content/50 text-xs">{@badge}</span>
    </div>
    """
  end

  defp product_sheet_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("World sheet")}
        subtitle={gettext("Entity connected to dialogue, quest state and export")}
        badge={gettext("Character profile")}
      />
      <div class="p-4 grid gap-3">
        <.sheet_row label={gettext("Character")} desc={gettext("Captain Ilya - rank, trust, inventory, scene tags")} status={gettext("Live")} />
        <.sheet_row label={gettext("Faction")} desc={gettext("Harbor Guild - resources, favors, reputation and routes")} status={gettext("Linked")} />
        <.sheet_row label={gettext("Quest State")} desc={gettext("Act II - quarantine, forged seal, inner harbor access")} status={gettext("Tracked")} />
        <.sheet_row label={gettext("Inherited Blocks")} desc={gettext("Stats, progress flags and consequence table")} status={gettext("Shared")} />
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :desc, :string, required: true
  attr :status, :string, required: true

  defp sheet_row(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-[140px_1fr_auto] gap-3 items-center p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3">
      <strong class="text-sm text-base-content">{@label}</strong>
      <span class="text-base-content/50 text-xs leading-relaxed">{@desc}</span>
      <span class="badge badge-sm bg-primary/10 text-primary border-primary/20">{@status}</span>
    </div>
    """
  end

  defp product_scene_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("Scene editor")}
        subtitle={gettext("Zones, pins, overlays and spatial links")}
        badge={gettext("Exploration mode")}
      />
      <div class="lp-scene-map relative min-h-[292px]">
        <div class="lp-zone z1"></div>
        <div class="lp-zone z2"></div>
        <div class="lp-zone z3"></div>
        <div class="lp-zone z4"></div>
        <div class="lp-pin p1"></div>
        <div class="lp-pin p2"></div>
        <div class="lp-pin p3"></div>
      </div>
    </section>
    """
  end

  defp product_localization_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("Localization")}
        subtitle={gettext("Progress by language, glossary and pending lines")}
        badge={gettext("DeepL ready")}
      />
      <div class="p-4 grid gap-3">
        <.locale_row lang="ES" width="100%" status={gettext("Ready")} />
        <.locale_row lang="EN" width="88%" status={gettext("Review")} />
        <.locale_row lang="FR" width="64%" status={gettext("In progress")} />
        <.locale_row lang="JA" width="32%" status={gettext("Blocked")} />
      </div>
    </section>
    """
  end

  attr :lang, :string, required: true
  attr :width, :string, required: true
  attr :status, :string, required: true

  defp locale_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[64px_1fr_auto] gap-3 items-center p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3">
      <strong class="text-sm text-base-content">{@lang}</strong>
      <div class="relative h-2.5 rounded-full bg-base-content/8 overflow-hidden">
        <span
          class="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-primary to-primary/70"
          style={"width: #{@width};"}
        >
        </span>
      </div>
      <em class="not-italic text-xs text-base-content/50">{@status}</em>
    </div>
    """
  end

  @screenplay_sample """
  INT. HARBOR WATCH - NIGHT

  CAPTAIN ILYA
  The harbor is still closed.

  PROTAGONIST
  I'm not here to break the quarantine. I'm here to avoid it.

  IF rep_guardia >= 4
    ILYA lowers her spear.
  ELSE
    The watch tightens around the gate.\
  """

  defp product_screenplay_panel(assigns) do
    assigns = assign(assigns, :screenplay, String.trim(@screenplay_sample))

    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden p-4">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-4">
        <div>
          <strong class="block text-base tracking-tight text-base-content">
            {gettext("Screenplay sync")}
          </strong>
          <span class="text-base-content/50 text-xs">
            {gettext("Professional script reading with flow synchronization")}
          </span>
        </div>
        <span class="text-base-content/50 text-xs">Courier Prime</span>
      </div>
      <div class="rounded-2xl border border-base-content/8 bg-base-content/3 p-5">
        <pre class="m-0 text-base-content/70 text-sm leading-relaxed whitespace-pre-wrap font-mono">{@screenplay}</pre>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────
  # Feature Grid
  # ──────────────────────────────────────────────

  @feature_colors ~w(primary accent secondary primary accent secondary)

  def feature_grid(assigns) do
    features = [
      %{num: "01", title: gettext("Sheets as source of truth"), desc: gettext("Characters, factions, quests, locations and items live in reusable structures with variables, formulas and inheritance.")},
      %{num: "02", title: gettext("Flows you can test"), desc: gettext("The value is not just the visual tree: it's being able to debug, simulate and verify it without exporting to another tool.")},
      %{num: "03", title: gettext("Scenes with real exploration"), desc: gettext("The spatial layer helps you think about the world as an interactive experience, not just as narrative documentation.")},
      %{num: "04", title: gettext("Story Player and Debug Mode"), desc: gettext("Test the story as a player or inspect it step by step with variables and conditions visible.")},
      %{num: "05", title: gettext("Integrated localization"), desc: gettext("Extract lines, translate, use glossaries and track coverage per language from the same narrative base.")},
      %{num: "06", title: gettext("Export for multiple engines"), desc: gettext("From Storyarn to Yarn Spinner, Ink, Unity, Godot Dialogic, Unreal or writing tools without redoing the work.")}
    ]

    assigns = assign(assigns, :features, Enum.zip(features, @feature_colors))

    ~H"""
    <section class="py-16 lg:py-20" id="features">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("One platform for interactive narrative")}
          description={gettext("Storyarn is a real working ecosystem: data, branches, scenes, screenplays and localization all living inside the same project.")}
        />

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <article
            :for={{feature, color} <- @features}
            class="p-6 rounded-3xl border border-base-content/8 bg-base-200/60"
          >
            <em class={"inline-flex items-center justify-center min-w-[46px] min-h-[46px] rounded-xl mb-4 not-italic font-extrabold tracking-tight text-#{color} bg-#{color}/10"}>
              {feature.num}
            </em>
            <h3 class="mb-3 text-xl tracking-tight font-bold text-base-content">{feature.title}</h3>
            <p class="text-base-content/60 leading-relaxed">{feature.desc}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────
  # Section Header (reusable)
  # ──────────────────────────────────────────────

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

  # ──────────────────────────────────────────────
  # Discover Section (tabbed interactive)
  # ──────────────────────────────────────────────

  def discover_section(assigns) do
    ~H"""
    <section class="py-16 lg:py-20" id="discover">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("Discover the product pillars")}
          description={gettext("This section summarizes the main tools in Storyarn. Understand the platform architecture at a glance: global vision, structured modeling, visual authoring and scenes.")}
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
                description={gettext("Project-level dashboards make the platform readable at a glance: scale, content health, warnings, localization progress and shipping readiness.")}
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
                description={gettext("Worldbuilding becomes data instead of scattered notes. Every entity lives in a reusable structure with depth and internal logic.")}
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
                description={gettext("A visual authoring surface for dialogue trees, checks, branches and consequences with a workflow that feels familiar to narrative teams.")}
                items={[
                  gettext("Clear graph editing for dialogue, conditions, instructions and exits."),
                  gettext("Nodes pull from live project data instead of disconnected text fragments."),
                  gettext("Strong fit for teams coming from articy:draft or Arcweaver.")
                ]}
              />
              <.discover_step
                feature="scenes"
                number={gettext("Feature 04")}
                title={gettext("Scenes")}
                description={gettext("Scene tools help teams think spatially before engineering: layers, zones, pins and map surfaces turn environments into usable design assets.")}
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
        subtitle={gettext("Storyarn starts at project level: key metrics, warnings, coverage, exports and status across the full production pipeline.")}
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
        subtitle={gettext("Characters, factions, locations and item logic live in a connected system with variables, blocks and inheritance.")}
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
        subtitle={gettext("Familiar to anyone coming from articy:draft or Arcweaver, but wired directly into sheets, scenes, drafts and export.")}
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
              {gettext(
                "Nodes pull from live project data instead of disconnected text fragments"
              )}
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
        subtitle={gettext("Layered maps, zones and pins make scenes readable as systems, not as loose concept art or disconnected layout files.")}
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
              {gettext(
                "Spatial structure for narrative beats, triggers and world readability"
              )}
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

  # ──────────────────────────────────────────────
  # Exploration Mode Spotlight
  # ──────────────────────────────────────────────

  def exploration_spotlight(assigns) do
    ~H"""
    <section class="py-16 lg:py-20" id="exploration-mode">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="p-8 rounded-[2rem] border border-base-content/8 bg-base-200/60">
          <div class="grid grid-cols-1 lg:grid-cols-[1.1fr_minmax(320px,0.72fr)] gap-6 items-start">
            <div class="grid gap-4">
              <span class="text-base-content/70 text-xs font-bold tracking-widest uppercase">
                {gettext("Exploration Mode")}
              </span>
              <h3 class="text-[clamp(2rem,4vw,3.6rem)] leading-[0.94] tracking-[-0.05em] font-bold text-base-content">
                {gettext("Turn scene design into a playable prototype.")}
              </h3>
              <p class="text-base-content/60 leading-relaxed">
                {gettext(
                  "This is where Storyarn stops feeling like documentation and starts feeling like a game. Zones, pins, camera behavior, state and flow triggers come together in a surface that teams can explore, test and show."
                )}
              </p>
              <ul class="grid gap-3 list-none p-0">
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext("Built to compete with dead documents, slide decks and unread GDDs.")}
                </li>
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext(
                    "Strong fit for CRPG, point-and-click and narrative exploration workflows."
                  )}
                </li>
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext(
                    "Useful for internal demos, publisher pitches and early playtest loops."
                  )}
                </li>
              </ul>
            </div>
            <div class="flex justify-end items-start">
              <span class="badge badge-ghost badge-sm">
                {gettext("Playable prototype engine")}
              </span>
            </div>
          </div>

          <div class="lp-exploration-shell mt-6">
            <div class="lp-exploration-map">
              <div class="lp-exploration-zone"></div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────
  # Version History Spotlight
  # ──────────────────────────────────────────────

  def version_spotlight(assigns) do
    ~H"""
    <section class="py-16 lg:py-20" id="version-history">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="p-8 rounded-[2rem] border border-base-content/8 bg-base-200/60">
          <div class="grid grid-cols-1 lg:grid-cols-[minmax(320px,0.72fr)_1.1fr] gap-6 items-start">
            <.version_visual />
            <.version_copy />
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp version_visual(assigns) do
    ~H"""
    <div class="lp-version-shot">
      <div class="lp-version-overlay">
        <div class="w-full max-w-[360px] p-4 rounded-2xl border border-base-content/8 bg-base-300/90 backdrop-blur">
          <div class="flex items-center justify-between gap-3 mb-3.5">
            <strong class="text-base text-base-content">{gettext("Version History")}</strong>
          </div>
          <div class="grid gap-3">
            <.version_entry
              title={gettext("Restored from v8")}
              tag="v11"
              line1={gettext("Mar 12, 2026 at 15:59")}
            />
            <.version_entry
              title={gettext("Before restore to v8")}
              tag="v10"
              line1={gettext("Auto snapshot before destructive restore")}
              line2={gettext("Safe rollback path preserved")}
            />
            <.version_entry
              title={gettext("Draft checkpoint")}
              tag={gettext("Draft")}
              line1={gettext("Private branch for scene edits and experimentation")}
              line2={gettext("Ready to compare, keep or discard")}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :tag, :string, required: true
  attr :line1, :string, required: true
  attr :line2, :string, default: nil

  defp version_entry(assigns) do
    ~H"""
    <div class="grid gap-2 p-3.5 rounded-2xl border border-base-content/6 bg-base-content/3">
      <div class="flex items-center gap-2.5">
        <span class="w-3.5 h-3.5 rounded-full bg-accent/20 shadow-[0_0_0_1px_var(--color-accent)/22]">
        </span>
        <strong class="text-sm text-base-content">{@title}</strong>
        <span class="badge badge-xs badge-outline border-accent/30 text-accent">{@tag}</span>
      </div>
      <span class="text-base-content/50 text-xs">{@line1}</span>
      <small :if={@line2} class="text-base-content/40 text-xs">{@line2}</small>
    </div>
    """
  end

  defp version_copy(assigns) do
    ~H"""
    <div class="grid gap-4">
      <span class="text-base-content/70 text-xs font-bold tracking-widest uppercase">
        {gettext("Version History")}
      </span>
      <h3 class="text-[clamp(2rem,4vw,3.6rem)] leading-[0.94] tracking-[-0.05em] font-bold text-base-content">
        {gettext("Versioning that feels safe without feeling technical.")}
      </h3>
      <p class="text-base-content/60 leading-relaxed">
        {gettext(
          "Storyarn brings version history to sheets, flows and scenes in a way that feels native to narrative teams. The goal is not to teach Git. The goal is to let people experiment without fear."
        )}
      </p>
      <ul class="grid gap-3 list-none p-0">
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("Named versions, safe restore and private drafts for exploration.")}
        </li>
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("Designed around the feeling of \"I can always go back.\"")}
        </li>
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("A rare capability in narrative tooling and a strong differentiator.")}
        </li>
      </ul>
    </div>
    """
  end

  # ──────────────────────────────────────────────
  # Workflow Grid
  # ──────────────────────────────────────────────

  def workflow_grid(assigns) do
    steps = [
      %{num: "01", title: gettext("Define the world"), desc: gettext("Model characters, factions, items and narrative rules in sheets that feed the rest of the project.")},
      %{num: "02", title: gettext("Write and branch"), desc: gettext("Build dialogues, checks, instructions and subflows using a visual editor prepared for large changes.")},
      %{num: "03", title: gettext("Explore and debug"), desc: gettext("Walk through scenes, test overlays, run the story player and use debug mode to validate logic and pacing.")},
      %{num: "04", title: gettext("Localize and export"), desc: gettext("Bring the project to your production pipeline with text, screenplays, variables and branches ready for the engine.")}
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <section class="py-16 lg:py-20" id="workflow">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("From worldbuilding to shipped game")}
          description={gettext("Storyarn is not a standalone module but a connected flow from pre-production, iteration and shipping.")}
        />

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <article
            :for={step <- @steps}
            class="relative pt-16 px-5 pb-6 rounded-3xl border border-base-content/8 bg-base-200/60"
          >
            <span class="absolute left-5 top-5 text-base-content/20 text-3xl font-extrabold tracking-tight">
              {step.num}
            </span>
            <h3 class="mb-3 text-lg tracking-tight font-bold text-base-content">{step.title}</h3>
            <p class="text-base-content/60 leading-relaxed">{step.desc}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────
  # CTA / Waitlist
  # ──────────────────────────────────────────────

  def cta_waitlist(assigns) do
    ~H"""
    <section class="py-8 pb-24" id="cta">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div
          class="lp-cta-band relative overflow-hidden p-10 rounded-[2rem] border border-base-content/8 bg-base-200/80"
          id="waitlist"
        >
          <div class="relative z-1 flex flex-col lg:flex-row items-end justify-between gap-6">
            <div>
              <h2 class="mb-3 text-[clamp(2rem,3vw,3.4rem)] leading-[0.96] tracking-[-0.06em] font-bold text-base-content">
                {gettext("Ready to build your next narrative?")}
              </h2>
              <p class="mb-2 max-w-[40rem] text-base-content/60 leading-relaxed">
                {gettext(
                  "We're onboarding a small group of narrative designers and game studios. Join the waitlist and we'll send you an invite when your spot is ready."
                )}
              </p>
              <form
                action={~p"/waitlist"}
                method="post"
                class="flex flex-wrap gap-3 mt-6 max-w-[460px]"
              >
                <input
                  type="hidden"
                  name="_csrf_token"
                  value={Plug.CSRFProtection.get_csrf_token()}
                />
                <input
                  type="email"
                  name="waitlist[email]"
                  placeholder={gettext("you@studio.com")}
                  required
                  class="input input-bordered flex-1 min-w-[200px] rounded-full bg-base-100"
                />
                <button type="submit" class="btn btn-primary rounded-full gap-2">
                  {gettext("Join the waitlist")}
                  <.icon name="arrow-right" class="size-4" />
                </button>
              </form>
              <p class="mt-3 text-base-content/30 text-xs">
                {gettext("No spam. We'll only email you when it's time.")}
              </p>
            </div>

            <div class="flex-shrink-0">
              <a
                href="#product"
                class="btn btn-ghost rounded-full border border-base-content/10"
              >
                {gettext("Back to product")}
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────
  # Footer
  # ──────────────────────────────────────────────

  def landing_footer(assigns) do
    ~H"""
    <footer class="pb-8">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)] flex flex-col sm:flex-row justify-between gap-5 text-base-content/50 text-sm">
        <span>{gettext("Storyarn - Open narrative design platform")}</span>
        <div class="flex gap-6">
          <.link navigate={~p"/docs"} class="hover:text-base-content transition-colors">
            {gettext("Docs")}
          </.link>
          <.link navigate={~p"/contact"} class="hover:text-base-content transition-colors">
            {gettext("Contact")}
          </.link>
        </div>
      </div>
    </footer>
    """
  end

  # ──────────────────────────────────────────────
  # Discover section JS (scroll-driven tab switching)
  # ──────────────────────────────────────────────

  def discover_script(assigns) do
    ~H"""
    <script>
      (() => {
        const root = document.querySelector("[data-feature-shell]");
        if (!root) return;

        const scrollbox = document.querySelector("[data-feature-scrollbox]");
        const tabs = Array.from(root.querySelectorAll("[data-feature]"));
        const steps = Array.from(root.querySelectorAll("[data-feature-step]"));

        const setActive = (feature) => {
          root.dataset.activeFeature = feature;
          tabs.forEach((tab) => {
            tab.setAttribute("aria-selected", tab.dataset.feature === feature ? "true" : "false");
          });
          steps.forEach((step) => {
            step.classList.toggle("is-active", step.dataset.featureStep === feature);
          });
        };

        let ticking = false;

        const updateFromScroll = () => {
          const bounds = scrollbox
            ? scrollbox.getBoundingClientRect()
            : { top: 0, height: window.innerHeight };
          const targetLine = bounds.top + bounds.height * 0.24;
          let next = steps[0];
          let closest = Number.POSITIVE_INFINITY;

          steps.forEach((step) => {
            const rect = step.getBoundingClientRect();
            const center = rect.top + rect.height / 2;
            const distance = Math.abs(center - targetLine);
            if (distance < closest) {
              closest = distance;
              next = step;
            }
          });

          if (next) setActive(next.dataset.featureStep);
          ticking = false;
        };

        const handleScroll = () => {
          if (ticking) return;
          ticking = true;
          window.requestAnimationFrame(updateFromScroll);
        };

        tabs.forEach((tab) => {
          tab.addEventListener("click", () => {
            const feature = tab.dataset.feature;
            const target = root.querySelector(`[data-feature-step="${feature}"]`);
            if (!target) return;
            setActive(feature);
            if (scrollbox) {
              const top = scrollbox.scrollTop +
                (target.getBoundingClientRect().top - scrollbox.getBoundingClientRect().top) -
                scrollbox.clientHeight * 0.16;
              scrollbox.scrollTo({ top, behavior: "smooth" });
            } else {
              target.scrollIntoView({ behavior: "smooth", block: "center" });
            }
          });
        });

        (scrollbox || window).addEventListener("scroll", handleScroll, { passive: true });
        window.addEventListener("resize", handleScroll);
        setActive(root.dataset.activeFeature || "dashboard");
        updateFromScroll();
      })();
    </script>
    """
  end
end
