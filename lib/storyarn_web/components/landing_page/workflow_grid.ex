defmodule StoryarnWeb.Components.LandingPage.WorkflowGrid do
  @moduledoc """
  Workflow grid section for the landing page.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.TextComponents, only: [widont: 1]

  def workflow_grid(assigns) do
    steps = [
      %{
        num: "01",
        title: gettext("Define the world"),
        desc:
          gettext(
            "Model characters, factions, items, and narrative rules in sheets that feed every other tool."
          )
      },
      %{
        num: "02",
        title: gettext("Write and branch"),
        desc:
          gettext(
            "Build dialogue, conditions, instructions, and subflows in a visual editor built for production scale."
          )
      },
      %{
        num: "03",
        title: gettext("Explore and debug"),
        desc:
          gettext(
            "Walk through scenes, run the Story Player, and use debug mode to validate logic and pacing."
          )
      },
      %{
        num: "04",
        title: gettext("Localize and export"),
        desc:
          gettext(
            "Bring text, screenplays, variables, and branches to your engine — localized and production-ready."
          )
      }
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <section class="py-16 lg:py-20 scroll-mt-32" id="workflow">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("From worldbuilding to shipped game")}
          description={
            gettext(
              "A connected workflow from pre-production through iteration to export — not a set of disconnected modules."
            )
          }
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

  attr :title, :string, required: true
  attr :description, :string, required: true

  defp section_header(assigns) do
    ~H"""
    <div class="grid gap-4 mb-8 max-w-[56rem]">
      <h2 class="text-[clamp(2.2rem,3vw,3.8rem)] leading-[0.97] tracking-[-0.06em] font-bold max-w-[16ch] text-base-content">
        {widont(@title)}
      </h2>
      <p class="max-w-[36rem] text-base-content/60 leading-relaxed text-base">
        {widont(@description)}
      </p>
    </div>
    """
  end
end
