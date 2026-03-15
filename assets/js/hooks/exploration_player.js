/**
 * ExplorationPlayer hook — renders a scene with clickable zones and pins
 * for the exploration mode player.
 *
 * Data attributes:
 * - data-exploration: JSON object containing:
 *   { background_url, scene_width, scene_height, display_mode,
 *     default_center_x, default_center_y, zones[], pins[] }
 *
 * Display modes:
 * - fit: Scales to fit viewport (aspect-ratio wrapper, max-w-4xl)
 * - scaled: Native pixel dimensions with CRPG-style edge-scroll camera
 *
 * Zone/pin action types:
 * - instruction: Clickable, pushes "exploration_element_click"
 * - display: Shows label + current variable value
 * - none/navigate: Zones with target_type push "exploration_element_click"
 *
 * Movement system:
 * - Walkable zones define traversable area (is_walkable flag)
 * - Leader pin (is_leader) moves on click inside walkable area
 * - Party pins (is_playable, !is_leader) follow with delay + fan offset
 * - Point-in-polygon ray-casting for walkable area checks
 *
 * Visibility states:
 * - visible: Rendered normally
 * - hide: Not rendered
 * - disable: Rendered dimmed, not clickable
 */
import { createElement, MapPin, Star, User, Zap } from "lucide";

const PIN_ICONS = {
  location: MapPin,
  character: User,
  event: Zap,
  custom: Star,
};

// Camera constants
const EDGE_THRESHOLD = 60; // px from viewport edge to start scrolling
const MAX_SPEED = 800; // px/s at full edge
const KEY_SPEED = 600; // px/s for arrow keys

// Movement constants
const MOVEMENT_SPEED = 15; // %/s — leader movement speed
const PARTY_SPEED_FACTOR = 0.8; // party members move slower
const PARTY_DELAY_MS = 200; // ms before party starts following
const PARTY_SPREAD = 2; // % perpendicular offset for fan formation
const ARRIVAL_THRESHOLD = 0.3; // % distance to consider arrived

export const ExplorationPlayer = {
  mounted() {
    const data = JSON.parse(this.el.dataset.exploration || "{}");
    this.backgroundUrl = data.background_url;
    this.sceneWidth = data.scene_width || 800;
    this.sceneHeight = data.scene_height || 600;
    this.displayMode = data.display_mode || "fit";
    this.defaultZoom = data.default_zoom || 1.0;
    this.defaultCenterX = data.default_center_x ?? 50;
    this.defaultCenterY = data.default_center_y ?? 50;
    this.zones = data.zones || [];
    this.pins = data.pins || [];
    this.variables = {};
    this.showZones = false;

    // Movement state
    this.walkableZones = [];
    this.leaderPin = null;
    this.partyPins = [];
    this.leaderMoving = false;
    this.leaderCurrentX = 0;
    this.leaderCurrentY = 0;
    this.leaderTargetX = 0;
    this.leaderTargetY = 0;
    this.partyTargets = [];
    this.partyPositions = [];
    this.partyMoving = false;
    this._movementFrame = null;

    this.initMovementData();
    this.render();
    this.initMovementClickHandler();

    this.handleEvent("exploration_state_updated", ({ zones, pins, variables }) => {
      this.variables = variables || {};
      this.updateVisibility(zones, pins);
      this.updateDisplayZones();
      this.updateWalkableZones(zones);
    });

    this.handleEvent("toggle_show_zones", ({ show }) => {
      this.showZones = show;
      this.applyZoneColors();
    });

    this.handleEvent("set_zoom", ({ zoom }) => {
      if (this.displayMode !== "scaled" || !this.wrapperEl) return;
      this.zoom = zoom;
      this.wrapperEl.style.transform = `scale(${this.zoom})`;
      this.clampCamera();
      this.applyCameraTransform();
    });
  },

  destroyed() {
    this.destroyCamera();
    this.destroyMovement();
  },

  // ===========================================================================
  // Render
  // ===========================================================================

  render() {
    this.el.innerHTML = "";

    if (this.displayMode === "scaled") {
      this.renderScaledMode();
    } else {
      this.renderFitMode();
    }
  },

  renderFitMode() {
    const wrapper = document.createElement("div");
    wrapper.className = "exploration-wrapper";
    wrapper.style.position = "relative";
    wrapper.style.width = "100%";
    wrapper.style.aspectRatio = `${this.sceneWidth} / ${this.sceneHeight}`;
    wrapper.style.margin = "0 auto";
    wrapper.style.overflow = "hidden";
    wrapper.style.borderRadius = "0.5rem";

    this.renderBackground(wrapper, true);
    this.renderElements(wrapper);
    this.el.appendChild(wrapper);
  },

  renderScaledMode() {
    this.zoom = this.defaultZoom;

    // Camera div wraps the scene content and gets translated
    const camera = document.createElement("div");
    camera.className = "exploration-camera";
    this.cameraEl = camera;

    const wrapper = document.createElement("div");
    wrapper.className = "exploration-wrapper";
    wrapper.style.position = "relative";
    wrapper.style.transformOrigin = "0 0";
    wrapper.style.transform = `scale(${this.zoom})`;
    this.wrapperEl = wrapper;

    // Set wrapper dimensions — use scene dimensions or defer to image natural size
    if (this.sceneWidth && this.sceneHeight) {
      wrapper.style.width = `${this.sceneWidth}px`;
      wrapper.style.height = `${this.sceneHeight}px`;
    }

    this.renderBackground(wrapper, false);
    this.renderElements(wrapper);
    camera.appendChild(wrapper);
    this.el.appendChild(camera);

    // If no scene dimensions, wait for image to load and use natural size
    if (!this.sceneWidth || !this.sceneHeight) {
      const img = wrapper.querySelector("img");
      if (img) {
        const applyNatural = () => {
          if (img.naturalWidth && img.naturalHeight) {
            this.sceneWidth = img.naturalWidth;
            this.sceneHeight = img.naturalHeight;
            wrapper.style.width = `${this.sceneWidth}px`;
            wrapper.style.height = `${this.sceneHeight}px`;
            this.initCamera();
          }
        };
        if (img.complete && img.naturalWidth) {
          applyNatural();
        } else {
          img.addEventListener("load", applyNatural);
        }
      }
    } else {
      this.initCamera();
    }
  },

  renderBackground(wrapper, useFitAspectRatio) {
    if (!this.backgroundUrl) return;

    const img = document.createElement("img");
    img.src = this.backgroundUrl;
    img.alt = "Map";
    img.style.position = "absolute";
    img.style.inset = "0";
    img.style.width = "100%";
    img.style.height = "100%";
    img.style.objectFit = "fill";
    img.draggable = false;

    if (useFitAspectRatio) {
      const onLoad = () => {
        if (img.naturalWidth && img.naturalHeight) {
          wrapper.style.aspectRatio = `${img.naturalWidth} / ${img.naturalHeight}`;
        }
      };
      img.addEventListener("load", onLoad);
      if (img.complete && img.naturalWidth) onLoad();
    }

    wrapper.appendChild(img);
  },

  renderElements(wrapper) {
    for (const zone of this.zones) {
      const el = this.createZoneElement(zone);
      if (el) wrapper.appendChild(el);
    }
    for (const pin of this.pins) {
      const el = this.createPinElement(pin);
      if (el) wrapper.appendChild(el);
    }
  },

  // ===========================================================================
  // Camera System (scaled mode only)
  // ===========================================================================

  initCamera() {
    this.cameraX = 0;
    this.cameraY = 0;
    this.velocityX = 0;
    this.velocityY = 0;
    this.mouseX = -1;
    this.mouseY = -1;
    this.keysDown = new Set();
    this.lastFrameTime = 0;
    this.flowModePaused = false;
    this.cameraFollowLeader = false;

    // Set initial camera position from default center
    this.setInitialCameraPosition();

    // Bind event handlers (store refs for cleanup)
    this._onMouseMove = (e) => {
      this.mouseX = e.clientX;
      this.mouseY = e.clientY;
    };
    this._onKeyDown = (e) => {
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.key)) {
        this.keysDown.add(e.key);
        // Manual camera control disables auto-follow
        this.cameraFollowLeader = false;
      }
    };
    this._onKeyUp = (e) => {
      this.keysDown.delete(e.key);
    };
    this._onResize = () => {
      this.clampCamera();
      this.applyCameraTransform();
    };
    this._onMouseLeave = () => {
      this.mouseX = -1;
      this.mouseY = -1;
    };

    document.addEventListener("mousemove", this._onMouseMove);
    document.addEventListener("keydown", this._onKeyDown);
    document.addEventListener("keyup", this._onKeyUp);
    document.addEventListener("mouseleave", this._onMouseLeave);
    window.addEventListener("resize", this._onResize);

    // Start animation loop
    this.lastFrameTime = performance.now();
    this._animFrame = requestAnimationFrame((t) => this.cameraLoop(t));
  },

  destroyCamera() {
    if (this._animFrame) {
      cancelAnimationFrame(this._animFrame);
      this._animFrame = null;
    }
    if (this._onMouseMove) {
      document.removeEventListener("mousemove", this._onMouseMove);
      document.removeEventListener("keydown", this._onKeyDown);
      document.removeEventListener("keyup", this._onKeyUp);
      document.removeEventListener("mouseleave", this._onMouseLeave);
      window.removeEventListener("resize", this._onResize);
    }
  },

  // Effective dimensions after zoom
  scaledWidth() {
    return this.sceneWidth * (this.zoom || 1);
  },

  scaledHeight() {
    return this.sceneHeight * (this.zoom || 1);
  },

  setInitialCameraPosition() {
    const viewport = this.getViewportBounds();
    if (!viewport) return;

    // Center on leader pin if available, otherwise use scene default center
    const centerX = this.leaderPin ? this.leaderPin.position_x : this.defaultCenterX;
    const centerY = this.leaderPin ? this.leaderPin.position_y : this.defaultCenterY;

    const centerPx = {
      x: (centerX / 100) * this.scaledWidth(),
      y: (centerY / 100) * this.scaledHeight(),
    };

    // Position camera so that center point is in the middle of viewport
    this.cameraX = centerPx.x - viewport.width / 2;
    this.cameraY = centerPx.y - viewport.height / 2;

    this.clampCamera();
    this.applyCameraTransform();
  },

  getViewportBounds() {
    // The viewport is the player-main element (parent of the hook element)
    const viewport = this.el.closest(".player-main");
    if (!viewport) return null;
    const rect = viewport.getBoundingClientRect();
    return { width: rect.width, height: rect.height, left: rect.left, top: rect.top };
  },

  cameraLoop(timestamp) {
    const dt = Math.min((timestamp - this.lastFrameTime) / 1000, 0.05); // cap at 50ms
    this.lastFrameTime = timestamp;

    // Check if flow mode is active (map container has pointer-events-none)
    const mapContainer = this.el.parentElement;
    this.flowModePaused = mapContainer?.classList.contains("pointer-events-none");

    if (!this.flowModePaused) {
      // Auto-follow leader in scaled mode during movement
      if (this.cameraFollowLeader && this.leaderMoving) {
        this.followLeaderWithCamera(dt);
      } else {
        this.updateCameraVelocity(dt);
        this.cameraX += this.velocityX * dt;
        this.cameraY += this.velocityY * dt;
      }
      this.clampCamera();
      this.applyCameraTransform();
    } else {
      // Decelerate when paused
      this.velocityX *= 0.9;
      this.velocityY *= 0.9;
    }

    this._animFrame = requestAnimationFrame((t) => this.cameraLoop(t));
  },

  followLeaderWithCamera(dt) {
    const viewport = this.getViewportBounds();
    if (!viewport) return;

    // Target: center camera on leader (using scaled dimensions)
    const targetCamX = (this.leaderCurrentX / 100) * this.scaledWidth() - viewport.width / 2;
    const targetCamY = (this.leaderCurrentY / 100) * this.scaledHeight() - viewport.height / 2;

    // Smooth follow
    const lerp = 1 - 0.01 ** dt;
    this.cameraX += (targetCamX - this.cameraX) * lerp;
    this.cameraY += (targetCamY - this.cameraY) * lerp;
    this.velocityX = 0;
    this.velocityY = 0;
  },

  updateCameraVelocity(dt) {
    const viewport = this.getViewportBounds();
    if (!viewport) return;

    let targetVx = 0;
    let targetVy = 0;

    // Edge-scroll from mouse position
    if (this.mouseX >= 0 && this.mouseY >= 0) {
      const relX = this.mouseX - viewport.left;
      const relY = this.mouseY - viewport.top;

      // Only apply edge scroll if mouse is within viewport
      if (relX >= 0 && relX <= viewport.width && relY >= 0 && relY <= viewport.height) {
        // Left edge
        if (relX < EDGE_THRESHOLD) {
          targetVx -= MAX_SPEED * (1 - relX / EDGE_THRESHOLD);
        }
        // Right edge
        if (relX > viewport.width - EDGE_THRESHOLD) {
          targetVx += MAX_SPEED * (1 - (viewport.width - relX) / EDGE_THRESHOLD);
        }
        // Top edge
        if (relY < EDGE_THRESHOLD) {
          targetVy -= MAX_SPEED * (1 - relY / EDGE_THRESHOLD);
        }
        // Bottom edge
        if (relY > viewport.height - EDGE_THRESHOLD) {
          targetVy += MAX_SPEED * (1 - (viewport.height - relY) / EDGE_THRESHOLD);
        }
      }
    }

    // Keyboard input (additive)
    if (this.keysDown.has("ArrowLeft")) targetVx -= KEY_SPEED;
    if (this.keysDown.has("ArrowRight")) targetVx += KEY_SPEED;
    if (this.keysDown.has("ArrowUp")) targetVy -= KEY_SPEED;
    if (this.keysDown.has("ArrowDown")) targetVy += KEY_SPEED;

    // Smooth interpolation (ease-in/out)
    const lerp = 1 - 0.001 ** dt; // ~0.93 at 60fps
    this.velocityX += (targetVx - this.velocityX) * lerp;
    this.velocityY += (targetVy - this.velocityY) * lerp;

    // Kill tiny velocities
    if (Math.abs(this.velocityX) < 0.5) this.velocityX = 0;
    if (Math.abs(this.velocityY) < 0.5) this.velocityY = 0;
  },

  clampCamera() {
    const viewport = this.getViewportBounds();
    if (!viewport) return;

    const sw = this.scaledWidth();
    const sh = this.scaledHeight();

    if (sw <= viewport.width) {
      this.cameraX = -(viewport.width - sw) / 2;
    } else {
      this.cameraX = Math.max(0, Math.min(this.cameraX, sw - viewport.width));
    }

    if (sh <= viewport.height) {
      this.cameraY = -(viewport.height - sh) / 2;
    } else {
      this.cameraY = Math.max(0, Math.min(this.cameraY, sh - viewport.height));
    }
  },

  applyCameraTransform() {
    if (this.cameraEl) {
      this.cameraEl.style.transform = `translate(${-this.cameraX}px, ${-this.cameraY}px)`;
    }
  },

  // ===========================================================================
  // Movement System
  // ===========================================================================

  initMovementData() {
    // Collect walkable zones (visible ones only — hidden zones excluded)
    this.walkableZones = this.zones.filter(
      (z) => z.is_walkable && z.vertices && z.vertices.length >= 3 && z.visibility !== "hide",
    );

    // Find leader and party pins
    this.leaderPin = this.pins.find((p) => p.is_leader && p.is_playable);
    this.partyPins = this.pins.filter((p) => p.is_playable && !p.is_leader);

    if (this.leaderPin) {
      this.leaderCurrentX = this.leaderPin.position_x;
      this.leaderCurrentY = this.leaderPin.position_y;
      this.leaderTargetX = this.leaderCurrentX;
      this.leaderTargetY = this.leaderCurrentY;
    }

    // Init party positions at their DB positions
    this.partyPositions = this.partyPins.map((p) => ({
      id: p.id,
      x: p.position_x,
      y: p.position_y,
    }));
    this.partyTargets = this.partyPositions.map((p) => ({ ...p }));
  },

  initMovementClickHandler() {
    if (!this.leaderPin || this.walkableZones.length === 0) return;

    // Click on the wrapper (not zones/pins) to move the leader
    // We use a timeout to let zone/pin click handlers fire first
    this._onWrapperClick = (e) => {
      // Don't move if flow mode is active
      if (this.flowModePaused) return;

      // Don't move if clicking on a pin (pins have their own interaction)
      const clickedPin = e.target.closest("[data-element-type='pin']");
      if (clickedPin) return;

      const wrapper = this.el.querySelector(".exploration-wrapper");
      if (!wrapper) return;

      const rect = wrapper.getBoundingClientRect();
      const clickX = ((e.clientX - rect.left) / rect.width) * 100;
      const clickY = ((e.clientY - rect.top) / rect.height) * 100;

      if (this.isPointInWalkableArea(clickX, clickY)) {
        this.startMovement(clickX, clickY);
        this.showClickFeedback(e.clientX, e.clientY, true);
      } else {
        this.showClickFeedback(e.clientX, e.clientY, false);
      }
    };

    // Attach to the hook root so it catches clicks from zones too
    this.el.addEventListener("click", this._onWrapperClick);
  },

  destroyMovement() {
    if (this._movementFrame) {
      cancelAnimationFrame(this._movementFrame);
      this._movementFrame = null;
    }
    if (this._partyTimeout) {
      clearTimeout(this._partyTimeout);
      this._partyTimeout = null;
    }
    if (this._onWrapperClick) {
      this.el.removeEventListener("click", this._onWrapperClick);
    }
  },

  // ===========================================================================
  // Point-in-polygon (Ray-casting algorithm)
  // ===========================================================================

  isPointInWalkableArea(x, y) {
    for (const zone of this.walkableZones) {
      if (this.isPointInPolygon(x, y, zone.vertices)) {
        return true;
      }
    }
    return false;
  },

  isPointInPolygon(x, y, vertices) {
    let inside = false;
    for (let i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      const xi = vertices[i].x;
      const yi = vertices[i].y;
      const xj = vertices[j].x;
      const yj = vertices[j].y;

      const intersect = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
      if (intersect) inside = !inside;
    }
    return inside;
  },

  // ===========================================================================
  // Movement Animation
  // ===========================================================================

  startMovement(targetX, targetY) {
    this.leaderTargetX = targetX;
    this.leaderTargetY = targetY;
    this.leaderMoving = true;

    // Enable camera follow in scaled mode
    if (this.displayMode === "scaled") {
      this.cameraFollowLeader = true;
    }

    // Start party following after delay
    if (this._partyTimeout) clearTimeout(this._partyTimeout);
    this._partyTimeout = setTimeout(() => {
      this.startPartyFollowing();
    }, PARTY_DELAY_MS);

    // Start movement loop if not already running
    if (!this._movementFrame) {
      this._movementLastTime = performance.now();
      this._movementFrame = requestAnimationFrame((t) => this.movementLoop(t));
    }
  },

  movementLoop(timestamp) {
    const dt = Math.min((timestamp - this._movementLastTime) / 1000, 0.05);
    this._movementLastTime = timestamp;

    let anyMoving = false;

    // Move leader
    if (this.leaderMoving) {
      anyMoving = this.stepLeader(dt) || anyMoving;
    }

    // Move party members
    if (this.partyMoving) {
      anyMoving = this.stepParty(dt) || anyMoving;
    }

    if (anyMoving) {
      this._movementFrame = requestAnimationFrame((t) => this.movementLoop(t));
    } else {
      this._movementFrame = null;
      this.cameraFollowLeader = false;
    }
  },

  stepLeader(dt) {
    const dx = this.leaderTargetX - this.leaderCurrentX;
    const dy = this.leaderTargetY - this.leaderCurrentY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (dist < ARRIVAL_THRESHOLD) {
      this.leaderCurrentX = this.leaderTargetX;
      this.leaderCurrentY = this.leaderTargetY;
      this.leaderMoving = false;
      this.updateLeaderDom();
      return false;
    }

    const step = MOVEMENT_SPEED * dt;
    const ratio = Math.min(step / dist, 1);
    const nextX = this.leaderCurrentX + dx * ratio;
    const nextY = this.leaderCurrentY + dy * ratio;

    // Boundary check: verify next position is still in walkable area
    if (this.isPointInWalkableArea(nextX, nextY)) {
      this.leaderCurrentX = nextX;
      this.leaderCurrentY = nextY;
      this.updateLeaderDom();
      return true;
    }

    // Can't move further — stop
    this.leaderMoving = false;
    return false;
  },

  stepParty(dt) {
    let anyMoving = false;

    for (let i = 0; i < this.partyPositions.length; i++) {
      const pos = this.partyPositions[i];
      const target = this.partyTargets[i];
      if (!target) continue;

      const dx = target.x - pos.x;
      const dy = target.y - pos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < ARRIVAL_THRESHOLD) {
        pos.x = target.x;
        pos.y = target.y;
      } else {
        const step = MOVEMENT_SPEED * PARTY_SPEED_FACTOR * dt;
        const ratio = Math.min(step / dist, 1);
        const nextX = pos.x + dx * ratio;
        const nextY = pos.y + dy * ratio;

        // Party members use simpler boundary check
        if (this.isPointInWalkableArea(nextX, nextY)) {
          pos.x = nextX;
          pos.y = nextY;
          anyMoving = true;
        }
      }

      this.updatePartyPinDom(this.partyPins[i].id, pos.x, pos.y);
    }

    if (!anyMoving) {
      this.partyMoving = false;
    }
    return anyMoving;
  },

  startPartyFollowing() {
    if (this.partyPins.length === 0) return;

    // Calculate movement direction for fan formation
    const dx = this.leaderTargetX - this.leaderCurrentX;
    const dy = this.leaderTargetY - this.leaderCurrentY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    // Perpendicular direction for spread
    let perpX = 0;
    let perpY = 1;
    if (dist > 0.1) {
      perpX = -dy / dist;
      perpY = dx / dist;
    }

    // Compute fan formation targets around the leader's target
    for (let i = 0; i < this.partyPins.length; i++) {
      const offset = (i - (this.partyPins.length - 1) / 2) * PARTY_SPREAD;
      // Party targets are offset behind and to the side of the leader target
      const behindOffset = PARTY_SPREAD; // slightly behind leader
      const ndx = dist > 0.1 ? dx / dist : 0;
      const ndy = dist > 0.1 ? dy / dist : 0;
      this.partyTargets[i] = {
        id: this.partyPins[i].id,
        x: this.leaderTargetX - ndx * behindOffset + perpX * offset,
        y: this.leaderTargetY - ndy * behindOffset + perpY * offset,
      };
    }

    this.partyMoving = true;

    // Restart movement loop if needed
    if (!this._movementFrame) {
      this._movementLastTime = performance.now();
      this._movementFrame = requestAnimationFrame((t) => this.movementLoop(t));
    }
  },

  // ===========================================================================
  // DOM Updates for Movement
  // ===========================================================================

  updateLeaderDom() {
    if (!this.leaderPin) return;
    const el = this.el.querySelector(
      `[data-element-type="pin"][data-element-id="${this.leaderPin.id}"]`,
    );
    if (el) {
      el.style.left = `${this.leaderCurrentX}%`;
      el.style.top = `${this.leaderCurrentY}%`;
      el.style.transition = "none";
    }
  },

  updatePartyPinDom(pinId, x, y) {
    const el = this.el.querySelector(`[data-element-type="pin"][data-element-id="${pinId}"]`);
    if (el) {
      el.style.left = `${x}%`;
      el.style.top = `${y}%`;
      el.style.transition = "none";
    }
  },

  // ===========================================================================
  // Click Feedback
  // ===========================================================================

  showClickFeedback(clientX, clientY, walkable) {
    const ring = document.createElement("div");
    ring.className = walkable ? "click-feedback-walkable" : "click-feedback-blocked";
    ring.style.position = "fixed";
    ring.style.left = `${clientX}px`;
    ring.style.top = `${clientY}px`;
    ring.style.transform = "translate(-50%, -50%)";
    ring.style.pointerEvents = "none";
    ring.style.zIndex = "9999";
    document.body.appendChild(ring);

    ring.addEventListener("animationend", () => ring.remove());
  },

  // ===========================================================================
  // Walkable Zone Updates
  // ===========================================================================

  updateWalkableZones(zoneStates) {
    // Refresh walkable zones considering visibility changes
    const visibilityMap = new Map();
    for (const z of zoneStates || []) {
      visibilityMap.set(String(z.id), z.visibility);
    }

    this.walkableZones = this.zones.filter((z) => {
      if (!z.is_walkable || !z.vertices || z.vertices.length < 3) return false;
      const vis = visibilityMap.get(String(z.id)) || z.visibility;
      return vis !== "hide";
    });
  },

  // ===========================================================================
  // Zone/Pin Creation (shared by both modes)
  // ===========================================================================

  createZoneElement(zone) {
    const { vertices, visibility } = zone;
    if (!vertices || vertices.length < 3) return null;
    if (visibility === "hide") return null;

    const isDisabled = visibility === "disable";
    const actionType = zone.action_type || "none";
    const hasTarget = zone.target_type && zone.target_id;
    const isWalkableOnly =
      zone.is_walkable && !hasTarget && (actionType === "none" || actionType === "walkable");
    const isClickable =
      !isDisabled && (actionType === "instruction" || actionType === "collection" || hasTarget);

    // Zone overlay with clip-path
    const div = document.createElement("div");
    div.className = `interaction-zone interaction-zone-${actionType}`;
    div.dataset.zoneId = zone.id;
    div.dataset.walkable = zone.is_walkable ? "true" : "false";
    div.style.position = "absolute";
    div.style.inset = "0";
    div.style.clipPath = `polygon(${vertices.map((v) => `${v.x}% ${v.y}%`).join(", ")})`;

    const fillColor = zone.fill_color || "#3b82f6";
    const opacity = zone.opacity != null ? zone.opacity : 0.3;
    div.dataset.fillColor = fillColor;
    div.dataset.fillOpacity = opacity;

    // Walkable-only zones: invisible by default, green tint when Show Zones
    if (this.showZones) {
      if (isWalkableOnly) {
        div.style.backgroundColor = "#4ade80";
        div.style.opacity = isDisabled ? 0.1 : 0.2;
      } else {
        div.style.backgroundColor = fillColor;
        div.style.opacity = isDisabled ? opacity * 0.3 : opacity;
      }
    } else {
      div.style.backgroundColor = "transparent";
      div.style.opacity = "1";
    }

    // Walkable-only zones are not clickable for actions — movement is handled by wrapper click
    if (isClickable) {
      div.style.pointerEvents = "auto";
      div.style.cursor = "pointer";
      div.style.transition = "background-color 0.15s";

      div.addEventListener("mouseenter", () => {
        if (!this.showZones) {
          div.style.backgroundColor = "rgba(255,255,255,0.08)";
        }
      });
      div.addEventListener("mouseleave", () => {
        if (!this.showZones) {
          div.style.backgroundColor = "transparent";
        }
      });
    } else if (isWalkableOnly) {
      // Walkable-only zones pass clicks through to wrapper for movement
      div.style.pointerEvents = "none";
    }

    // Click handler — single consolidated event
    if (isClickable) {
      div.addEventListener("click", () => {
        this.pushEvent("exploration_element_click", {
          element_type: "zone",
          element_id: zone.id,
          action_type: actionType,
          action_data: zone.action_data || {},
          target_type: zone.target_type || null,
          target_id: zone.target_id || null,
        });
      });
    }

    // Label container (centered in bounding box)
    const bbox = this.getBoundingBox(vertices);
    const labelContainer = document.createElement("div");
    labelContainer.dataset.role = "label-container";
    labelContainer.style.position = "absolute";
    labelContainer.style.left = `${bbox.minX}%`;
    labelContainer.style.top = `${bbox.minY}%`;
    labelContainer.style.width = `${bbox.maxX - bbox.minX}%`;
    labelContainer.style.height = `${bbox.maxY - bbox.minY}%`;
    labelContainer.style.display = "flex";
    labelContainer.style.flexDirection = "column";
    labelContainer.style.alignItems = "center";
    labelContainer.style.justifyContent = "center";
    labelContainer.style.pointerEvents = "none";

    if (isDisabled) {
      labelContainer.style.opacity = "0.3";
    }

    // Walkable-only zones: hide label in exploration (they define area, not interaction)
    if (isWalkableOnly) {
      labelContainer.style.display = "none";
    } else if (actionType === "display") {
      const ref = zone.action_data?.variable_ref;
      const label = document.createElement("span");
      label.className = "zone-display-label";
      label.textContent = zone.name;
      labelContainer.appendChild(label);

      const value = document.createElement("span");
      value.className = "zone-display-value";
      if (ref) value.dataset.ref = ref;
      value.textContent = this.variables[ref] ?? "—";
      labelContainer.appendChild(value);
    } else {
      const label = document.createElement("span");
      label.className = "zone-label";
      label.textContent = zone.name;
      labelContainer.appendChild(label);
    }

    // Group wrapper
    const group = document.createElement("div");
    group.style.position = "absolute";
    group.style.inset = "0";
    group.style.pointerEvents = "none";
    group.dataset.elementType = "zone";
    group.dataset.elementId = zone.id;
    group.appendChild(div);
    group.appendChild(labelContainer);

    return group;
  },

  createPinElement(pin) {
    const { visibility } = pin;
    if (visibility === "hide") return null;

    const isDisabled = visibility === "disable";
    const actionType = pin.action_type || "none";
    const hasTarget = pin.target_type && pin.target_id;
    const isClickable = !isDisabled && (actionType === "instruction" || hasTarget);

    const color = pin.color || "#3b82f6";
    const size = pin.size || "md";
    const iconSize = { sm: 16, md: 22, lg: 30 }[size] || 22;
    const markerSize = { sm: 28, md: 36, lg: 48 }[size] || 36;

    // Container positioned at pin coordinates
    const container = document.createElement("div");
    container.style.position = "absolute";
    container.style.left = `${pin.position_x}%`;
    container.style.top = `${pin.position_y}%`;
    container.style.transform = "translate(-50%, -50%)";
    container.style.display = "flex";
    container.style.flexDirection = "column";
    container.style.alignItems = "center";
    container.style.gap = "2px";
    container.style.zIndex = "10";
    container.dataset.elementType = "pin";
    container.dataset.elementId = pin.id;

    if (isDisabled) {
      container.style.opacity = "0.3";
      container.style.pointerEvents = "none";
    }

    // Pin marker (circle with icon or avatar)
    const marker = document.createElement("div");
    marker.style.width = `${markerSize}px`;
    marker.style.height = `${markerSize}px`;
    marker.style.borderRadius = "50%";
    marker.style.backgroundColor = color;
    marker.style.display = "flex";
    marker.style.alignItems = "center";
    marker.style.justifyContent = "center";
    marker.style.boxShadow = "0 2px 6px rgba(0,0,0,0.4)";
    marker.style.border = "2px solid rgba(255,255,255,0.6)";
    marker.style.transition = "transform 0.15s, box-shadow 0.15s";
    marker.style.flexShrink = "0";

    // Leader pin gets a subtle crown glow
    if (pin.is_leader) {
      marker.style.border = "2px solid rgba(250,204,21,0.8)";
      marker.style.boxShadow = "0 2px 8px rgba(250,204,21,0.3), 0 2px 6px rgba(0,0,0,0.4)";
    }

    if (isClickable) {
      marker.style.cursor = "pointer";

      marker.addEventListener("mouseenter", () => {
        marker.style.transform = "scale(1.15)";
        marker.style.boxShadow = "0 3px 10px rgba(0,0,0,0.5)";
      });
      marker.addEventListener("mouseleave", () => {
        marker.style.transform = "scale(1)";
        marker.style.boxShadow = pin.is_leader
          ? "0 2px 8px rgba(250,204,21,0.3), 0 2px 6px rgba(0,0,0,0.4)"
          : "0 2px 6px rgba(0,0,0,0.4)";
      });

      marker.addEventListener("click", () => {
        this.pushEvent("exploration_element_click", {
          element_type: "pin",
          element_id: pin.id,
          action_type: actionType,
          action_data: pin.action_data || {},
          target_type: pin.target_type || null,
          target_id: pin.target_id || null,
        });
      });
    }

    // Avatar or icon inside marker
    if (pin.avatar_url) {
      const avatar = document.createElement("img");
      avatar.src = pin.avatar_url;
      avatar.style.width = "100%";
      avatar.style.height = "100%";
      avatar.style.borderRadius = "50%";
      avatar.style.objectFit = "cover";
      avatar.draggable = false;
      marker.style.padding = "0";
      marker.style.overflow = "hidden";
      marker.appendChild(avatar);
    } else if (pin.icon_asset_url) {
      const icon = document.createElement("img");
      icon.src = pin.icon_asset_url;
      icon.style.width = `${iconSize}px`;
      icon.style.height = `${iconSize}px`;
      icon.style.objectFit = "contain";
      icon.draggable = false;
      marker.appendChild(icon);
    } else {
      const IconClass = PIN_ICONS[pin.pin_type] || PIN_ICONS.location;
      const iconEl = createElement(IconClass, {
        width: iconSize,
        height: iconSize,
        color: "#fff",
        strokeWidth: 2,
      });
      marker.appendChild(iconEl);
    }

    container.appendChild(marker);

    // Label below pin
    if (pin.label) {
      const label = document.createElement("span");
      label.className = "zone-label";
      label.style.fontSize = "10px";
      label.style.maxWidth = "80px";
      label.style.textAlign = "center";
      label.style.overflow = "hidden";
      label.style.textOverflow = "ellipsis";
      label.style.whiteSpace = "nowrap";
      label.textContent = pin.label;
      container.appendChild(label);
    }

    return container;
  },

  // ===========================================================================
  // Helpers
  // ===========================================================================

  getBoundingBox(vertices) {
    let minX = 100,
      minY = 100,
      maxX = 0,
      maxY = 0;
    for (const v of vertices) {
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }
    return { minX, minY, maxX, maxY };
  },

  updateVisibility(zones, pins) {
    const wrapper = this.el.querySelector(".exploration-wrapper");
    if (!wrapper) return;

    // Update zone visibility
    for (const zoneState of zones || []) {
      const group = wrapper.querySelector(
        `[data-element-type="zone"][data-element-id="${zoneState.id}"]`,
      );

      if (zoneState.visibility === "hide") {
        if (group) group.style.display = "none";
      } else if (zoneState.visibility === "disable") {
        if (group) {
          group.style.display = "";
          const overlay = group.querySelector(".interaction-zone");
          if (overlay) {
            overlay.style.opacity = "0.1";
            overlay.style.pointerEvents = "none";
            overlay.style.cursor = "default";
          }
          const labelContainer = group.querySelector('[data-role="label-container"]');
          if (labelContainer) labelContainer.style.opacity = "0.3";
        }
      } else {
        if (group) {
          group.style.display = "";
          const overlay = group.querySelector(".interaction-zone");
          if (overlay) {
            const zone = this.zones.find((z) => String(z.id) === String(zoneState.id));
            if (this.showZones && zone) {
              if (
                zone.is_walkable &&
                !zone.target_type &&
                ["none", "walkable"].includes(zone.action_type || "none")
              ) {
                overlay.style.backgroundColor = "#4ade80";
                overlay.style.opacity = 0.2;
              } else {
                overlay.style.backgroundColor = zone.fill_color || "#3b82f6";
                overlay.style.opacity = zone.opacity != null ? zone.opacity : 0.3;
              }
            } else {
              overlay.style.backgroundColor = "transparent";
              overlay.style.opacity = "1";
            }
            const actionType =
              overlay.dataset?.actionType || overlay.className.match(/interaction-zone-(\w+)/)?.[1];
            const hasTarget = zone?.target_type && zone?.target_id;
            if (actionType === "instruction" || hasTarget) {
              overlay.style.pointerEvents = "auto";
              overlay.style.cursor = "pointer";
            }
          }
          const labelContainer = group.querySelector('[data-role="label-container"]');
          if (labelContainer) labelContainer.style.opacity = "1";
        }
      }
    }

    // Update pin visibility
    for (const pinState of pins || []) {
      const el = wrapper.querySelector(
        `[data-element-type="pin"][data-element-id="${pinState.id}"]`,
      );

      if (pinState.visibility === "hide") {
        if (el) el.style.display = "none";
      } else if (pinState.visibility === "disable") {
        if (el) {
          el.style.display = "";
          el.style.opacity = "0.3";
          el.style.pointerEvents = "none";
        }
      } else {
        if (el) {
          el.style.display = "";
          el.style.opacity = "1";
          el.style.pointerEvents = "auto";
        }
      }
    }
  },

  applyZoneColors() {
    const overlays = this.el.querySelectorAll(".interaction-zone");
    for (const overlay of overlays) {
      if (this.showZones) {
        const isWalkable = overlay.dataset.walkable === "true";
        const zone = this.zones.find((z) => String(z.id) === overlay.dataset.zoneId);
        const isWalkableOnly =
          isWalkable &&
          zone &&
          !zone.target_type &&
          ["none", "walkable"].includes(zone.action_type || "none");

        if (isWalkableOnly) {
          overlay.style.backgroundColor = "#4ade80";
          overlay.style.opacity = 0.2;
        } else {
          const fillColor = overlay.dataset.fillColor || "#3b82f6";
          const opacity = parseFloat(overlay.dataset.fillOpacity) || 0.3;
          overlay.style.backgroundColor = fillColor;
          overlay.style.opacity = opacity;
        }
      } else {
        overlay.style.backgroundColor = "transparent";
        overlay.style.opacity = "1";
      }
    }
  },

  updateDisplayZones() {
    const displayValues = this.el.querySelectorAll(".zone-display-value[data-ref]");
    for (const el of displayValues) {
      const ref = el.dataset.ref;
      el.textContent = this.variables[ref] ?? "—";
    }
  },
};
