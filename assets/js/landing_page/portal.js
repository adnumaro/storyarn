/**
 * Hero portal — Three.js WebGL shader-based energy ring.
 * Renders directly with built-in shader glow.
 * Exports a public API for click-to-zoom animation.
 */

import * as THREE from "three";
import { fragmentShader, vertexShader } from "./portal_shader.js";

let portalAPI = null;

const isMobile = /Android|iPhone|iPad/i.test(navigator.userAgent) || window.innerWidth < 768;

function initPortal() {
  const canvas = document.getElementById("portal-canvas");
  const portalFrame = document.getElementById("portal-video-frame");
  if (!canvas || canvas.dataset.initialized) return;
  canvas.dataset.initialized = "true";

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Renderer
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: false,
      powerPreference: isMobile ? "low-power" : "high-performance",
    });
  } catch {
    canvas.closest(".lp-portal-wrap")?.classList.add("lp-portal-fallback");
    return;
  }
  renderer.setPixelRatio(isMobile ? 1 : Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);

  // Scene + Camera
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);

  // Shader uniforms
  const uniforms = {
    uTime: { value: 0 },
    uIntensity: { value: 1.0 },
    uScale: { value: 1.0 },
    uResolution: { value: new THREE.Vector2() },
    uPortalCenter: { value: new THREE.Vector2() },
    uPortalMaxWidth: { value: 0 },
  };

  const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });

  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material);
  scene.add(quad);

  // Resize
  const stage = canvas.parentElement;
  const bufferSize = new THREE.Vector2();

  function resize() {
    if (!stage) return;

    const rect = stage.getBoundingClientRect();
    const width = Math.round(rect.width);
    const height = Math.round(rect.height);

    if (width <= 0 || height <= 0) {
      return;
    }

    renderer.setSize(width, height, false);
    renderer.getDrawingBufferSize(bufferSize);
    uniforms.uResolution.value.copy(bufferSize);

    const scaleX = bufferSize.x / width;
    const scaleY = bufferSize.y / height;
    const frameRect = portalFrame?.getBoundingClientRect();

    stage?.style.setProperty("--lp-portal-center-x", `${width * 0.5}px`);
    stage?.style.setProperty("--lp-portal-center-y", `${height * 0.72}px`);

    if (frameRect) {
      const minPortalWidth = window.innerWidth < 640 ? 1240 : 1020;
      const localCenterX = frameRect.left - rect.left + frameRect.width * 0.5;
      const localCenterY = frameRect.top - rect.top + frameRect.height * 0.5;
      const portalYOffset = Math.min(frameRect.height * 0.28, window.innerWidth < 640 ? 112 : 156);
      const maxPortalWidth = Math.min(Math.max(frameRect.width * 2.05 + 900, minPortalWidth), 2220);
      const portalCenterY = localCenterY + portalYOffset;

      stage?.style.setProperty("--lp-portal-center-x", `${localCenterX}px`);
      stage?.style.setProperty("--lp-portal-center-y", `${portalCenterY}px`);

      uniforms.uPortalCenter.value.set(
        localCenterX * scaleX,
        (height - localCenterY - portalYOffset) * scaleY,
      );
      uniforms.uPortalMaxWidth.value = maxPortalWidth * scaleX;
      return;
    }

    uniforms.uPortalCenter.value.set(bufferSize.x * 0.5, bufferSize.y * 0.5);
    uniforms.uPortalMaxWidth.value = Math.min(width * 0.92, 1360) * scaleX;
  }

  // Animation loop
  let raf;
  const clock = new THREE.Clock();

  function loop() {
    uniforms.uTime.value = clock.getElapsedTime();
    renderer.render(scene, camera);
    raf = requestAnimationFrame(loop);
  }

  resize();

  if (reduced) {
    uniforms.uTime.value = 0;
    renderer.render(scene, camera);
  } else {
    loop();
  }

  // Resize handler
  let resizeTimer;
  let resizeObserver = null;
  const onResize = () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(resize, 150);
  };

  window.addEventListener("resize", onResize);

  if (stage && "ResizeObserver" in window) {
    resizeObserver = new ResizeObserver(() => resize());
    resizeObserver.observe(stage);
    if (portalFrame) {
      resizeObserver.observe(portalFrame);
    }
  }

  // Cleanup
  function dispose() {
    if (raf) cancelAnimationFrame(raf);
    clearTimeout(resizeTimer);
    window.removeEventListener("resize", onResize);
    resizeObserver?.disconnect();
    renderer.dispose();
    material.dispose();
    quad.geometry.dispose();
    delete canvas.dataset.initialized;
    portalAPI = null;
  }

  window.addEventListener("phx:page-loading-start", dispose, { once: true });

  // Public API for scroll animation
  portalAPI = {
    setIntensity(v) {
      uniforms.uIntensity.value = v;
    },
    setScale(v) {
      uniforms.uScale.value = v;
    },
    dispose,
  };
}

export function getPortalAPI() {
  return portalAPI;
}

initPortal();
window.addEventListener("phx:page-loading-stop", initPortal);
