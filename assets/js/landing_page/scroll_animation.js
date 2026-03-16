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

  function portalFrameRect() {
    return portalFrame.getBoundingClientRect();
  }

  function openFullscreen() {
    const portal = getPortalAPI();

    if (reduced || !portal) {
      fullscreen.appendChild(video);
      portalTrigger.classList.add("is-active");
      video.classList.add("is-fullscreen");
      fullscreen.classList.add("is-active");
      video.muted = false;
      video.volume = 1;
      return;
    }

    // Fade out all surrounding UI
    gsap.to(heroContent, {
      opacity: 0,
      y: -30,
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

    // Calculate target: centered in viewport, 92vw wide, 16:9
    const targetW = Math.min(window.innerWidth * 0.92, 1400);
    const targetH = targetW * (9 / 16);
    const targetX = (window.innerWidth - targetW) / 2;
    const targetY = (window.innerHeight - targetH) / 2;

    // Move the video out of transformed ancestors before animating it in the viewport.
    portalTrigger.classList.add("is-active");
    fullscreen.appendChild(video);
    video.style.position = "fixed";
    video.style.top = `${videoRect.top}px`;
    video.style.left = `${videoRect.left}px`;
    video.style.width = `${videoRect.width}px`;
    video.style.height = `${videoRect.height}px`;
    video.style.transform = "none";
    video.style.zIndex = "99999";
    video.style.pointerEvents = "none";

    // Animate video position, size, and mask gradient
    const maskProxy = { solid: 25, fade: 46 };

    gsap.to(video, {
      top: targetY,
      left: targetX,
      width: targetW,
      height: targetH,
      borderRadius: 12,
      duration: 1.15,
      ease: "power3.in",
      onComplete() {
        // Move video to fullscreen overlay, reset inline styles
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
      },
    });

    gsap.to(maskProxy, {
      solid: 100,
      fade: 100,
      duration: 1.0,
      ease: "power2.in",
      onUpdate() {
        setVideoMask(video, maskProxy.solid, maskProxy.fade);
      },
    });

    // Portal zoom + volume
    const proxy = { scale: 1, intensity: 1, vol: 0 };

    gsap.to(proxy, {
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
    });
  }

  function closeFullscreen() {
    const portal = getPortalAPI();

    if (reduced || !portal) {
      fullscreen.classList.remove("is-active");
      video.classList.remove("is-fullscreen");
      portalFrame.appendChild(video);
      video.muted = true;
      clearVideoMask(video);
      portalTrigger.classList.remove("is-active");
      return;
    }

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
    const targetRadius = window.getComputedStyle(portalFrame).borderRadius;

    // Keep the video fixed during the closing flight, then dock it back into the portal.
    video.classList.remove("is-fullscreen");
    fullscreen.classList.remove("is-active");

    // Animate from fullscreen back into the portal opening.
    video.style.position = "fixed";
    video.style.top = `${videoRect.top}px`;
    video.style.left = `${videoRect.left}px`;
    video.style.width = `${videoRect.width}px`;
    video.style.height = `${videoRect.height}px`;
    video.style.transform = "none";
    video.style.zIndex = "99999";
    video.style.pointerEvents = "none";
    video.style.objectFit = "cover";
    video.style.borderRadius = startRadius;
    clearVideoMask(video);

    const maskProxy = { solid: 100, fade: 100 };

    gsap.to(video, {
      top: targetRect.top,
      left: targetRect.left,
      width: targetRect.width,
      height: targetRect.height,
      borderRadius: targetRadius,
      duration: 0.6,
      ease: "power2.out",
      onComplete() {
        video.style.cssText = "";
        clearVideoMask(video);
        portalFrame.appendChild(video);
        portalTrigger.classList.remove("is-active");
      },
    });

    gsap.to(maskProxy, {
      solid: 25,
      fade: 46,
      duration: 0.5,
      delay: 0.1,
      ease: "power2.out",
      onUpdate() {
        setVideoMask(video, maskProxy.solid, maskProxy.fade);
      },
    });

    if (portal && !reduced) {
      // Zoom portal back
      const zoomProxy = { scale: 12, intensity: 3 };
      gsap.to(zoomProxy, {
        scale: 1,
        intensity: 1,
        duration: 0.6,
        ease: "power2.out",
        onUpdate() {
          portal.setScale(zoomProxy.scale);
          portal.setIntensity(zoomProxy.intensity);
        },
      });
    }

    // Fade all UI back in
    gsap.to(heroContent, {
      opacity: 1,
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
