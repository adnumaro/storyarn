/**
 * Portal click-to-zoom — clicking the portal zooms the camera in,
 * animates the video from portal position to fullscreen, and fades sound in.
 * Topbar stays visible (fullscreen z-index < header z-index).
 */

import { gsap } from "gsap";
import { getPortalAPI } from "./portal.js";

function setVideoMask(video, solidPct, fadePct) {
  const mask = `radial-gradient(circle at 50% 50%, black ${solidPct}%, transparent ${fadePct}%)`;
  video.style.maskImage = mask;
  video.style.webkitMaskImage = mask;
}

function clearVideoMask(video) {
  video.style.maskImage = "";
  video.style.webkitMaskImage = "";
}

function initPortalClick() {
  const portalTrigger = document.getElementById("portal-trigger");
  const portalFrame = document.getElementById("portal-video-frame");
  const portalBadge = portalTrigger?.querySelector(".lp-portal-trigger-badge");
  const heroContent = document.getElementById("hero-content");
  const fullscreen = document.getElementById("portal-fullscreen");
  const closeBtn = document.getElementById("portal-fullscreen-close");
  const video = document.getElementById("portal-video");

  if (!portalTrigger || !portalFrame || !fullscreen || !video) return;
  if (portalTrigger.dataset.clickInitialized) return;
  portalTrigger.dataset.clickInitialized = "true";

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Elements to fade out during portal entry
  const topbar = document.querySelector(".landing-shell > header");
  const landingPage = document.querySelector(".landing-page");
  const fullscreenShadow = "0 40px 120px rgba(0, 0, 0, 0.46)";
  let currentTimeline = null;
  let isTransitioning = false;

  gsap.set(heroContent, { yPercent: -10 });

  function portalFrameRect() {
    return portalFrame.getBoundingClientRect();
  }

  function killActiveTweens() {
    currentTimeline?.kill();
    currentTimeline = null;

    gsap.killTweensOf([heroContent, topbar, landingPage, portalFrame, portalBadge, video]);
  }

  function restorePortalChrome() {
    portalFrame.style.opacity = "";

    if (portalBadge) {
      portalBadge.style.opacity = "";
    }
  }

  function setFlyingVideoRect(rect, radius, boxShadow) {
    video.style.position = "fixed";
    video.style.top = `${rect.top}px`;
    video.style.left = `${rect.left}px`;
    video.style.width = `${rect.width}px`;
    video.style.height = `${rect.height}px`;
    video.style.transform = "none";
    video.style.zIndex = "99999";
    video.style.pointerEvents = "none";
    video.style.objectFit = "cover";
    video.style.borderRadius = radius;
    video.style.boxShadow = boxShadow;
  }

  function resolvedBoxShadow(boxShadow) {
    if (!boxShadow || boxShadow === "none") {
      return fullscreenShadow;
    }

    return boxShadow;
  }

  function openFullscreen() {
    const portal = getPortalAPI();

    if (isTransitioning || fullscreen.classList.contains("is-active")) return;

    if (reduced || !portal) {
      fullscreen.appendChild(video);
      portalTrigger.classList.add("is-active");
      video.classList.add("is-fullscreen");
      fullscreen.classList.add("is-active");
      video.muted = false;
      video.volume = 1;
      return;
    }

    isTransitioning = true;
    killActiveTweens();
    restorePortalChrome();

    // Fade out all surrounding UI
    gsap.to(heroContent, {
      opacity: 0,
      yPercent: -10,
      y: -48,
      duration: 0.5,
      ease: "power2.in",
    });

    if (topbar) {
      gsap.to(topbar, {
        opacity: 0,
        y: -20,
        duration: 0.4,
        ease: "power2.in",
        onComplete() {
          topbar.style.visibility = "hidden";
        },
      });
    }

    if (landingPage) {
      gsap.to(landingPage, {
        opacity: 0,
        duration: 0.5,
        ease: "power2.in",
      });
    }

    // Unmute with volume at 0, then fade in
    try {
      video.muted = false;
      video.volume = 0;
    } catch {
      // Autoplay policy may block unmute outside user gesture on some browsers
    }

    // Animate video position from the portal opening to centered fullscreen.
    const videoRect = portalFrameRect();
    const frameStyle = window.getComputedStyle(portalFrame);
    const startRadius = frameStyle.borderRadius;
    const startShadow = resolvedBoxShadow(frameStyle.boxShadow);

    // Calculate target: centered in viewport, 92vw wide, 16:9
    const targetW = Math.min(window.innerWidth * 0.92, 1400);
    const targetH = targetW * (9 / 16);
    const targetX = (window.innerWidth - targetW) / 2;
    const targetY = (window.innerHeight - targetH) / 2;

    // Move the video out of transformed ancestors before animating it in the viewport.
    portalTrigger.classList.add("is-active");
    fullscreen.appendChild(video);
    setFlyingVideoRect(videoRect, startRadius, startShadow);

    // Animate video position, size, and mask gradient
    const maskProxy = { solid: 25, fade: 46 };
    const proxy = { scale: 1, intensity: 1, vol: 0 };

    currentTimeline = gsap.timeline({
      onComplete() {
        video.style.cssText = "";
        fullscreen.appendChild(video);
        video.classList.add("is-fullscreen");
        fullscreen.classList.add("is-active");
        clearVideoMask(video);
        try {
          video.volume = 1;
        } catch {
          // fallback
        }
        currentTimeline = null;
        isTransitioning = false;
      },
    });

    currentTimeline.to(
      video,
      {
        top: targetY,
        left: targetX,
        width: targetW,
        height: targetH,
        borderRadius: 12,
        boxShadow: fullscreenShadow,
        duration: 1.22,
        ease: "power3.in",
      },
      0,
    );

    currentTimeline.to(
      maskProxy,
      {
        solid: 100,
        fade: 100,
        duration: 1.0,
        ease: "power2.in",
        onUpdate() {
          setVideoMask(video, maskProxy.solid, maskProxy.fade);
        },
      },
      0,
    );

    currentTimeline.to(
      portalFrame,
      {
        opacity: 0,
        duration: 0.52,
        ease: "power2.inOut",
      },
      0.22,
    );

    if (portalBadge) {
      currentTimeline.to(
        portalBadge,
        {
          opacity: 0,
          duration: 0.34,
          ease: "power2.inOut",
        },
        0.16,
      );
    }

    currentTimeline.to(
      proxy,
      {
        scale: 12,
        intensity: 3,
        vol: 1,
        duration: 1.4,
        ease: "power3.in",
        onUpdate() {
          portal.setScale(proxy.scale);
          portal.setIntensity(proxy.intensity);
          try {
            video.volume = proxy.vol;
          } catch {
            // volume setter may fail
          }
        },
      },
      0,
    );
  }

  function closeFullscreen() {
    const portal = getPortalAPI();

    if (isTransitioning || !fullscreen.classList.contains("is-active")) return;

    if (reduced || !portal) {
      fullscreen.classList.remove("is-active");
      video.classList.remove("is-fullscreen");
      portalFrame.appendChild(video);
      video.muted = true;
      clearVideoMask(video);
      portalTrigger.classList.remove("is-active");
      return;
    }

    isTransitioning = true;
    killActiveTweens();

    // Fade volume out
    const volProxy = { vol: video.volume || 1 };
    gsap.to(volProxy, {
      vol: 0,
      duration: 0.4,
      onUpdate() {
        try {
          video.volume = volProxy.vol;
        } catch {
          // volume setter may fail
        }
      },
      onComplete() {
        video.muted = true;
      },
    });

    // Get current fullscreen position
    const videoRect = video.getBoundingClientRect();
    const startRadius = window.getComputedStyle(video).borderRadius;
    const targetRect = portalFrameRect();
    const frameStyle = window.getComputedStyle(portalFrame);
    const targetRadius = frameStyle.borderRadius;
    const targetShadow = resolvedBoxShadow(frameStyle.boxShadow);

    // Keep the video fixed during the closing flight, then dock it back into the portal.
    video.classList.remove("is-fullscreen");
    fullscreen.classList.remove("is-active");
    portalTrigger.classList.add("is-active");

    // Animate from fullscreen back into the portal opening.
    setFlyingVideoRect(
      videoRect,
      startRadius,
      resolvedBoxShadow(window.getComputedStyle(video).boxShadow),
    );
    clearVideoMask(video);

    const maskProxy = { solid: 100, fade: 100 };
    const zoomProxy = { scale: 12, intensity: 3 };

    currentTimeline = gsap.timeline({
      onComplete() {
        video.style.cssText = "";
        clearVideoMask(video);
        portalFrame.appendChild(video);
        portalTrigger.classList.remove("is-active");
        restorePortalChrome();
        currentTimeline = null;
        isTransitioning = false;
      },
    });

    currentTimeline.to(
      video,
      {
        top: targetRect.top,
        left: targetRect.left,
        width: targetRect.width,
        height: targetRect.height,
        borderRadius: targetRadius,
        boxShadow: targetShadow,
        duration: 0.72,
        ease: "power2.out",
      },
      0,
    );

    currentTimeline.to(
      maskProxy,
      {
        solid: 25,
        fade: 46,
        duration: 0.58,
        ease: "power2.out",
        onUpdate() {
          setVideoMask(video, maskProxy.solid, maskProxy.fade);
        },
      },
      0.08,
    );

    currentTimeline.to(
      portalFrame,
      {
        opacity: 1,
        duration: 0.18,
        ease: "power2.inOut",
      },
      0.56,
    );

    if (portalBadge) {
      currentTimeline.to(
        portalBadge,
        {
          opacity: 1,
          duration: 0.18,
          ease: "power2.inOut",
        },
        0.62,
      );
    }

    if (portal && !reduced) {
      // Zoom portal back
      currentTimeline.to(
        zoomProxy,
        {
          scale: 1,
          intensity: 1,
          duration: 0.6,
          ease: "power2.out",
          onUpdate() {
            portal.setScale(zoomProxy.scale);
            portal.setIntensity(zoomProxy.intensity);
          },
        },
        0,
      );
    }

    // Fade all UI back in
    gsap.to(heroContent, {
      opacity: 1,
      yPercent: -10,
      y: 0,
      duration: 0.5,
      ease: "power2.out",
      delay: 0.2,
    });

    if (topbar) {
      topbar.style.visibility = "visible";
      gsap.to(topbar, {
        opacity: 1,
        y: 0,
        duration: 0.4,
        ease: "power2.out",
        delay: 0.2,
      });
    }

    if (landingPage) {
      gsap.to(landingPage, {
        opacity: 1,
        duration: 0.5,
        ease: "power2.out",
        delay: 0.3,
      });
    }
  }

  portalTrigger.addEventListener("click", openFullscreen);

  if (closeBtn) {
    closeBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      closeFullscreen();
    });
  }

  // Escape key closes fullscreen
  const onKeyDown = (e) => {
    if (e.key === "Escape" && fullscreen.classList.contains("is-active")) {
      closeFullscreen();
    }
  };
  document.addEventListener("keydown", onKeyDown);

  // Cleanup on navigation
  window.addEventListener(
    "phx:page-loading-start",
    () => {
      killActiveTweens();
      restorePortalChrome();
      portalTrigger.removeEventListener("click", openFullscreen);
      document.removeEventListener("keydown", onKeyDown);
      delete portalTrigger.dataset.clickInitialized;
    },
    { once: true },
  );
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initPortalClick);
} else {
  initPortalClick();
}
window.addEventListener("phx:page-loading-stop", initPortalClick);
