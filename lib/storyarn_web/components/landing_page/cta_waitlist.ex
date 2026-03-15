defmodule StoryarnWeb.Components.LandingPage.CtaWaitlist do
  @moduledoc """
  CTA / Waitlist section for the landing page.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.TextComponents, only: [widont: 1]

  def cta_waitlist(assigns) do
    ~H"""
    <section class="py-8 pb-24 scroll-mt-32" id="cta">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div
          class="lp-cta-band relative overflow-hidden p-10 rounded-[2rem] border border-base-content/8 bg-base-200/80"
          id="waitlist"
        >
          <div class="relative z-1 flex flex-col lg:flex-row items-end justify-between gap-6">
            <div>
              <h2 class="mb-3 text-[clamp(2rem,3vw,3.4rem)] leading-[0.96] tracking-[-0.06em] font-bold text-base-content">
                {widont(gettext("Ready to build your next narrative?"))}
              </h2>
              <p class="mb-2 max-w-[40rem] text-base-content/60 leading-relaxed">
                {widont(
                  gettext(
                    "We're onboarding a small group of narrative designers and game studios. Join the waitlist and we'll send you an invite when your spot is ready."
                  )
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
end
