/**
 * Discover section — 3D monitor with rotating screenshots.
 * Exports a public API for section_scroll.js to drive sub-step transitions.
 */

import * as THREE from "three";
import { RoundedBoxGeometry } from "three/examples/jsm/geometries/RoundedBoxGeometry.js";
import { gsap } from "gsap";
import { captureException } from "../utils/sentry";

let monitorAPI = null;
let monitorReadyResolve = null;
const monitorReady = new Promise((resolve) => { monitorReadyResolve = resolve; });

const isMobile = /Android|iPhone|iPad/i.test(navigator.userAgent) || window.innerWidth < 768;

const SCREEN_IMAGES = [
  "/images/landing/discovery-sheets.png",
  "/images/landing/discovery-flows.png",
  "/images/landing/discovery-scenes.png",
];

// Monitor rotation/position per sub-step
const SUB_STEPS = [
  // Sheets: rotated left, monitor shifted right → text goes left
  { rotY: -0.58, rotZ: 0.03, posX: 0.75, camZ: 0, yOffset: 0 },
  // Flows: rotated right, monitor shifted left → text goes right
  { rotY: 0.58, rotZ: -0.03, posX: -0.75, camZ: 0, yOffset: 0 },
  // Scenes: frontal, zoom in, push down
  { rotY: 0, rotZ: 0, posX: 0, camZ: -1.8, yOffset: -1 },
];

function createRoundedRectShape(width, height, radius) {
  const shape = new THREE.Shape();
  const x = -width / 2;
  const y = -height / 2;

  shape.moveTo(x + radius, y);
  shape.lineTo(x + width - radius, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + radius);
  shape.lineTo(x + width, y + height - radius);
  shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  shape.lineTo(x + radius, y + height);
  shape.quadraticCurveTo(x, y + height, x, y + height - radius);
  shape.lineTo(x, y + radius);
  shape.quadraticCurveTo(x, y, x + radius, y);

  return shape;
}

function createCurvedPlane(width, height, curveRadius, segmentsX, segmentsY) {
  const geo = new THREE.PlaneGeometry(width, height, segmentsX, segmentsY);
  const pos = geo.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const angle = x / curveRadius;
    pos.setX(i, Math.sin(angle) * curveRadius);
    pos.setZ(i, curveRadius - Math.cos(angle) * curveRadius);
  }
  pos.needsUpdate = true;
  geo.computeVertexNormals();
  return geo;
}

function curveBox(geometry, curveRadius) {
  const pos = geometry.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);
    const angle = x / curveRadius;
    const curvedZ = curveRadius - Math.cos(angle) * curveRadius;
    pos.setX(i, Math.sin(angle) * curveRadius);
    pos.setZ(i, curvedZ + z);
  }
  pos.needsUpdate = true;
  geometry.computeVertexNormals();
  return geometry;
}

function createMonitorGroup(textures) {
  const group = new THREE.Group();

  const screenW = 3.2;
  const screenH = 2.0;
  const bezelPad = 0.08;
  const bezelW = screenW + bezelPad * 2;
  const bezelH = screenH + bezelPad * 2;
  const bodyDepth = 0.18;
  const curveRadius = 8;
  const segments = 40;

  // ── 3D rounded body (flat front, rounded corners) ──
  const bodyGeo = new RoundedBoxGeometry(bezelW, bezelH, bodyDepth, 3, 0.04);

  const bodyMat = new THREE.MeshPhysicalMaterial({
    color: 0x111122,
    roughness: 0.22,
    metalness: 0.85,
    clearcoat: 0.3,
    clearcoatRoughness: 0.15,
  });
  const body = new THREE.Mesh(bodyGeo, bodyMat);
  group.add(body);

  // ── Front bezel inset (darker recessed area around screen) ──
  const insetGeo = new THREE.PlaneGeometry(screenW + 0.02, screenH + 0.02);
  const insetMat = new THREE.MeshStandardMaterial({
    color: 0x0a0a14,
    roughness: 0.9,
    metalness: 0.1,
  });
  const inset = new THREE.Mesh(insetGeo, insetMat);
  inset.position.z = bodyDepth / 2 + 0.003;
  group.add(inset);

  // ── Screen (two planes for crossfade) ──
  const screenGeo = new THREE.PlaneGeometry(screenW, screenH);
  const screenMatA = new THREE.MeshBasicMaterial({
    map: textures[0] || null,
    toneMapped: false,
    transparent: true,
    opacity: 1,
  });
  const screenMatB = new THREE.MeshBasicMaterial({
    toneMapped: false,
    transparent: true,
    opacity: 0,
  });
  const screenA = new THREE.Mesh(screenGeo, screenMatA);
  const screenB = new THREE.Mesh(screenGeo.clone(), screenMatB);
  screenA.position.z = bodyDepth / 2 + 0.005;
  screenB.position.z = bodyDepth / 2 + 0.006;
  group.add(screenA);
  group.add(screenB);

  return { group, screenA, screenB, screenMatA, screenMatB };
}

function initDiscoverMonitor() {
  const canvas = document.getElementById("discover-monitor-canvas");
  if (!canvas || canvas.dataset.initialized) {
    monitorReadyResolve?.();
    return;
  }

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || isMobile) {
    monitorReadyResolve?.();
    return;
  }

  canvas.dataset.initialized = "true";

  // Renderer
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: true,
      powerPreference: "high-performance",
    });
  } catch (e) {
    captureException(e, { component: "discover-monitor", phase: "renderer-init" });
    return;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);

  // Scene + Camera
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
  const BASE_CAM_Z = 4.8;
  camera.position.z = BASE_CAM_Z;

  // Lighting
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.4);
  scene.add(ambientLight);

  const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
  dirLight.position.set(2, 3, 5);
  scene.add(dirLight);

  const fillLight = new THREE.DirectionalLight(0x22d3ee, 0.15);
  fillLight.position.set(-3, -1, 3);
  scene.add(fillLight);

  // Create monitor (texture assigned once loaded)
  let monitor;
  try {
    monitor = createMonitorGroup([]);
    scene.add(monitor.group);
  } catch (e) {
    captureException(e, { component: "discover-monitor", phase: "monitor-create" });
    return;
  }

  // Load textures
  const loader = new THREE.TextureLoader();
  const textures = [];

  SCREEN_IMAGES.forEach((src, i) => {
    loader.load(
      src,
      (texture) => {
        texture.colorSpace = THREE.SRGBColorSpace;
        texture.minFilter = THREE.LinearFilter;
        texture.magFilter = THREE.LinearFilter;
        textures[i] = texture;

        // Show texture as soon as it loads for current step
        if (i === currentSubStep) {
          monitor.screenMatA.map = texture;
          monitor.screenMatA.needsUpdate = true;
          renderer.render(scene, camera);
          monitorReadyResolve?.();
        }
      },
      undefined,
      () => {
        textures[i] = null;
      },
    );
  });

  let currentSubStep = 0;
  let running = false;

  // Set initial state (Sheets: rotated left)
  const step0 = SUB_STEPS[0];
  monitor.group.rotation.y = step0.rotY;
  monitor.group.rotation.z = step0.rotZ;
  monitor.group.position.x = step0.posX;
  let animFrameId = null;

  // Resize
  const stage = canvas.parentElement;

  function computeMonitorY(camZ) {
    // Calculate visible height at monitor's z-distance from camera
    const fovRad = (camera.fov * Math.PI) / 180;
    const dist = camZ ?? camera.position.z;
    const visibleHeight = 2 * Math.tan(fovRad / 2) * dist;
    // Place monitor so its bottom edge (~screenH/2 below center) sits near canvas bottom
    // offset down = half visible height - half monitor height - small margin
    return -(visibleHeight / 2) + 1.0 + 0.6;
  }

  function resize() {
    if (!stage) return;
    const rect = stage.getBoundingClientRect();
    // Use viewport dimensions as fallback when section is off-screen
    const width = Math.round(rect.width > 0 ? rect.width : window.innerWidth);
    const height = Math.round(rect.height > 0 ? rect.height : window.innerHeight);
    if (width <= 0 || height <= 0) return;

    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();

    // Recompute monitor Y to keep it anchored near bottom
    const step = SUB_STEPS[currentSubStep];
    monitor.group.position.y = computeMonitorY(camera.position.z) + (step?.yOffset ?? 0);
  }

  resize();
  renderer.render(scene, camera);

  // Render loop
  function render() {
    if (!running) return;
    renderer.render(scene, camera);
    animFrameId = requestAnimationFrame(render);
  }

  function resume() {
    if (running) return;
    running = true;
    resize();
    // Ensure first frame has correct position before it's visible
    renderer.render(scene, camera);
    render();
  }

  function pause() {
    running = false;
    if (animFrameId) {
      cancelAnimationFrame(animFrameId);
      animFrameId = null;
    }
  }

  function setSubStep(index) {
    if (index < 0 || index >= SUB_STEPS.length) return;

    const target = SUB_STEPS[index];
    const prevStep = currentSubStep;
    currentSubStep = index;

    // Animate rotation & position
    gsap.to(monitor.group.rotation, {
      y: target.rotY,
      z: target.rotZ,
      duration: 0.8,
      ease: "power3.inOut",
    });

    gsap.to(monitor.group.position, {
      x: target.posX,
      duration: 0.8,
      ease: "power3.inOut",
    });

    // Camera zoom/position + monitor Y offset
    const targetCamZ = BASE_CAM_Z + target.camZ;
    gsap.to(camera.position, {
      z: targetCamZ,
      duration: 0.8,
      ease: "power3.inOut",
    });
    gsap.to(monitor.group.position, {
      y: computeMonitorY(targetCamZ) + target.yOffset,
      duration: 0.8,
      ease: "power3.inOut",
    });

    // Crossfade: new image fades in on top, old fades out underneath
    if (prevStep !== index && textures[index]) {
      // Put new texture on B layer (on top), fade it in
      monitor.screenMatB.map = textures[index];
      monitor.screenMatB.needsUpdate = true;
      monitor.screenMatB.opacity = 0;

      gsap.to(monitor.screenMatB, {
        opacity: 1,
        duration: 0.8,
        ease: "power2.inOut",
        onComplete() {
          // Swap: move new texture to A, reset B
          monitor.screenMatA.map = textures[index];
          monitor.screenMatA.needsUpdate = true;
          monitor.screenMatA.opacity = 1;
          monitor.screenMatB.opacity = 0;
        },
      });

      gsap.to(monitor.screenMatA, {
        opacity: 0,
        duration: 0.8,
        ease: "power2.inOut",
        onComplete() {
          monitor.screenMatA.opacity = 1;
        },
      });
    }
  }

  // Resize handler
  const onResize = () => {
    if (running) resize();
  };
  window.addEventListener("resize", onResize);

  // Cleanup on navigation
  window.addEventListener(
    "phx:page-loading-start",
    () => {
      pause();
      window.removeEventListener("resize", onResize);
      renderer.dispose();
      delete canvas.dataset.initialized;
      monitorAPI = null;
    },
    { once: true },
  );

  // Tab click → animate monitor directly (no cross-module dependency)
  const tabButtons = Array.from(
    document.querySelectorAll("[data-feature-shell] button[data-feature-tab]"),
  );
  tabButtons.forEach((btn, i) => {
    btn.addEventListener("click", () => {
      setSubStep(i);
    });
  });

  monitorAPI = { setSubStep, resume, pause };
}

export function getMonitorAPI() {
  return monitorAPI;
}

export function whenMonitorReady() {
  return monitorReady;
}

initDiscoverMonitor();
window.addEventListener("phx:page-loading-stop", initDiscoverMonitor);
