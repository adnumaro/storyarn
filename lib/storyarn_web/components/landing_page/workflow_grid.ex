defmodule StoryarnWeb.Components.LandingPage.WorkflowGrid do
  @moduledoc """
  Workflow grid section for the landing page.
  """
  use StoryarnWeb, :html

  def workflow_grid(assigns) do
    steps = [
      %{
        num: "01",
        title: gettext("Define the world"),
        desc:
          gettext(
            "Model characters, factions, items and narrative rules in sheets that feed the rest of the project."
          )
      },
      %{
        num: "02",
        title: gettext("Write and branch"),
        desc:
          gettext(
            "Build dialogues, checks, instructions and subflows using a visual editor prepared for large changes."
          )
      },
      %{
        num: "03",
        title: gettext("Explore and debug"),
        desc:
          gettext(
            "Walk through scenes, test overlays, run the story player and use debug mode to validate logic and pacing."
          )
      },
      %{
        num: "04",
        title: gettext("Localize and export"),
        desc:
          gettext(
            "Bring the project to your production pipeline with text, screenplays, variables and branches ready for the engine."
          )
      }
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <section class="py-16 lg:py-20" id="workflow">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("From worldbuilding to shipped game")}
          description={
            gettext(
              "Storyarn is not a standalone module but a connected flow from pre-production, iteration and shipping."
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
    <div class="flex flex-col lg:flex-row items-start lg:items-end justify-between gap-7 mb-8">
      <h2 class="text-[clamp(2.2rem,3vw,3.8rem)] leading-[0.97] tracking-[-0.06em] font-bold max-w-[12ch] text-base-content">
        {@title}
      </h2>
      <p class="max-w-[36rem] text-base-content/60 leading-relaxed text-base">{@description}</p>
    </div>
    """
  end
end
