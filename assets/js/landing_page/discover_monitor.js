/**
 * Discover section — 3D monitor with rotating screenshots.
 * Exports a public API for section_scroll.js to drive sub-step transitions.
 */

import * as THREE from "three";
import { gsap } from "gsap";

let monitorAPI = null;

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

function createMonitorGroup(textures) {
  const group = new THREE.Group();

  const screenW = 3.2;
  const screenH = 2.0;
  const bezelPad = 0.06;
  const bezelW = screenW + bezelPad * 2;
  const bezelH = screenH + bezelPad * 2;
  const bodyDepth = 0.06;
  const curveRadius = 8;
  const segments = 32;

  // Curved body (back panel)
  const bodyGeo = createCurvedPlane(bezelW, bezelH, curveRadius, segments, 1);
  const bodyMaterial = new THREE.MeshStandardMaterial({
    color: 0x1a1a2e,
    roughness: 0.3,
    metalness: 0.7,
    side: THREE.DoubleSide,
  });
  const body = new THREE.Mesh(bodyGeo, bodyMaterial);
  body.position.z = -bodyDepth;
  group.add(body);

  // Curved screen
  const screenGeometry = createCurvedPlane(screenW, screenH, curveRadius, segments, 1);
  const screenMaterial = new THREE.MeshBasicMaterial({
    map: textures[0] || null,
    toneMapped: false,
  });
  const screen = new THREE.Mesh(screenGeometry, screenMaterial);
  screen.position.z = 0.002;
  group.add(screen);

  // Curved gradient overlay
  const gradientCanvas = document.createElement("canvas");
  gradientCanvas.width = 4;
  gradientCanvas.height = 256;
  const ctx = gradientCanvas.getContext("2d");
  const gradient = ctx.createLinearGradient(0, 0, 0, 256);
  gradient.addColorStop(0, "rgba(10, 18, 26, 0)");
  gradient.addColorStop(0.5, "rgba(10, 18, 26, 0)");
  gradient.addColorStop(0.85, "rgba(10, 18, 26, 0.7)");
  gradient.addColorStop(1, "rgba(10, 18, 26, 1)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 4, 256);

  const gradientTexture = new THREE.CanvasTexture(gradientCanvas);
  const gradientMaterial = new THREE.MeshBasicMaterial({
    map: gradientTexture,
    transparent: true,
    depthWrite: false,
  });
  const gradientPlane = new THREE.Mesh(
    createCurvedPlane(screenW, screenH, curveRadius, segments, 1),
    gradientMaterial,
  );
  gradientPlane.position.z = 0.004;
  group.add(gradientPlane);

  // Edge frame (top, bottom, left, right curved strips)
  const frameMat = new THREE.MeshStandardMaterial({
    color: 0x252540,
    roughness: 0.2,
    metalness: 0.8,
  });

  // Top strip
  const topStrip = createCurvedPlane(bezelW, bezelPad, curveRadius, segments, 1);
  const topMesh = new THREE.Mesh(topStrip, frameMat);
  topMesh.position.y = screenH / 2 + bezelPad / 2;
  topMesh.position.z = 0.001;
  group.add(topMesh);

  // Bottom strip
  const botMesh = new THREE.Mesh(topStrip.clone(), frameMat);
  botMesh.position.y = -(screenH / 2 + bezelPad / 2);
  botMesh.position.z = 0.001;
  group.add(botMesh);

  // Subtle edge glow
  const rimGeo = createCurvedPlane(bezelW + 0.04, bezelH + 0.04, curveRadius, segments, 1);
  const rimMaterial = new THREE.MeshBasicMaterial({
    color: 0x22d3ee,
    transparent: true,
    opacity: 0.1,
    side: THREE.DoubleSide,
  });
  const rim = new THREE.Mesh(rimGeo, rimMaterial);
  rim.position.z = -0.001;
  group.add(rim);

  return { group, screen, screenMaterial };
}

function initDiscoverMonitor() {
  const canvas = document.getElementById("discover-monitor-canvas");
  if (!canvas || canvas.dataset.initialized) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || isMobile) return;

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
  } catch {
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
    console.log("[discover-monitor] Monitor group created OK");
  } catch (e) {
    console.error("[discover-monitor] createMonitorGroup CRASHED:", e);
    return;
  }

  // Load textures
  const loader = new THREE.TextureLoader();
  const textures = [];

  SCREEN_IMAGES.forEach((src, i) => {
    console.log(`[discover-monitor] Loading texture ${i}: ${src}`);
    loader.load(
      src,
      (texture) => {
        console.log(`[discover-monitor] Texture ${i} loaded OK:`, texture.image.width, "x", texture.image.height);
        texture.colorSpace = THREE.SRGBColorSpace;
        texture.minFilter = THREE.LinearFilter;
        texture.magFilter = THREE.LinearFilter;
        textures[i] = texture;

        // Show texture as soon as it loads for current step
        if (i === currentSubStep) {
          console.log(`[discover-monitor] Assigning texture ${i} to screen`);
          monitor.screenMaterial.map = texture;
          monitor.screenMaterial.needsUpdate = true;
          renderer.render(scene, camera);
        }
      },
      (progress) => {
        console.log(`[discover-monitor] Texture ${i} progress:`, progress);
      },
      (err) => {
        console.error(`[discover-monitor] Texture ${i} FAILED to load:`, src, err);
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
    const width = Math.round(rect.width);
    const height = Math.round(rect.height);
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
  console.log("[discover-monitor] Init done. Screen material:", monitor.screenMaterial, "Canvas size:", canvas.width, "x", canvas.height);

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
    console.log("[discover-monitor] setSubStep called:", index);
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

    // Swap texture at the midpoint of the animation
    if (prevStep !== index && textures[index]) {
      gsap.delayedCall(0.35, () => {
        monitor.screenMaterial.map = textures[index];
        monitor.screenMaterial.needsUpdate = true;
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
  console.log("[discover-monitor] Found tab buttons:", tabButtons.length, tabButtons.map(b => b.textContent.trim()));
  tabButtons.forEach((btn, i) => {
    btn.addEventListener("click", () => {
      console.log("[discover-monitor] Tab clicked:", i, btn.textContent.trim());
      setSubStep(i);
    });
  });

  monitorAPI = { setSubStep, resume, pause };
}

export function getMonitorAPI() {
  return monitorAPI;
}

initDiscoverMonitor();
window.addEventListener("phx:page-loading-stop", initDiscoverMonitor);
