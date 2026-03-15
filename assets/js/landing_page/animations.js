const initLandingAnimations = () => {
  if (document.querySelector("[data-lp-animations-initialized]")) return;

  const root = document.querySelector(".landing-shell");
  if (!root) return;

  root.setAttribute("data-lp-animations-initialized", "true");

  // ── Scroll-triggered reveal ──
  const revealElements = root.querySelectorAll("[data-reveal]");

  if (revealElements.length > 0) {
    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const el = entry.target;
            const delay = parseInt(el.dataset.revealDelay || "0", 10);
            setTimeout(() => el.classList.add("is-revealed"), delay);
            revealObserver.unobserve(el);
          }
        });
      },
      { threshold: 0.15, rootMargin: "0px 0px -80px 0px" },
    );

    revealElements.forEach((el) => {
      revealObserver.observe(el);
    });
  }

  // ── Count-up animation for metrics ──
  const countElements = root.querySelectorAll("[data-count-up]");

  if (countElements.length > 0) {
    const countObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;

          const el = entry.target;
          const target = el.dataset.countUp;
          const isPercent = target.includes("%");
          const numTarget = parseInt(target.replace("%", ""), 10);
          const duration = 1200;
          const start = performance.now();

          const animate = (now) => {
            const elapsed = now - start;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - (1 - progress) ** 3;
            const current = Math.round(numTarget * eased);
            el.textContent = isPercent ? `${current}%` : String(current);

            if (progress < 1) requestAnimationFrame(animate);
          };

          el.textContent = isPercent ? "0%" : "0";
          requestAnimationFrame(animate);
          countObserver.unobserve(el);
        });
      },
      { threshold: 0.5 },
    );

    countElements.forEach((el) => {
      countObserver.observe(el);
    });
  }

  // ── Progress bar animation ──
  const barElements = root.querySelectorAll("[data-bar-width]");

  if (barElements.length > 0) {
    const barObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;

          const el = entry.target;
          const targetWidth = el.dataset.barWidth;
          el.style.width = "0%";
          el.style.transition = "width 1s cubic-bezier(0.22, 1, 0.36, 1)";
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              el.style.width = targetWidth;
            });
          });
          barObserver.unobserve(el);
        });
      },
      { threshold: 0.3 },
    );

    barElements.forEach((el) => {
      barObserver.observe(el);
    });
  }
};

initLandingAnimations();
window.addEventListener("phx:page-loading-stop", initLandingAnimations);
