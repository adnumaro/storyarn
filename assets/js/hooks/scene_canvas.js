/**
 * SceneCanvas - Phoenix LiveView Hook for the interactive map editor.
 *
 * Thin orchestrator: delegates setup to scene_canvas/setup.js,
 * complex logic split into handler factories in scene_canvas/handlers/.
 */

import L from "leaflet";
import { createContextMenu } from "../scene_canvas/context_menu.js";
import { imageBounds, toPercent } from "../scene_canvas/coordinate_utils.js";
import { exportPNG, exportSVG } from "../scene_canvas/exporter.js";
import { createFloatingToolbar } from "../scene_canvas/floating_toolbar.js";
import { createAnnotationHandler } from "../scene_canvas/handlers/annotation_handler.js";
import { createConnectionHandler } from "../scene_canvas/handlers/connection_handler.js";
import { createLayerHandler } from "../scene_canvas/handlers/layer_handler.js";
import { createPinHandler } from "../scene_canvas/handlers/pin_handler.js";
import { createZoneHandler } from "../scene_canvas/handlers/zone_handler.js";
import { createMinimap } from "../scene_canvas/minimap.js";
import { createRuler } from "../scene_canvas/ruler.js";
import { addGridPlaceholder, initMap } from "../scene_canvas/setup.js";

export const SceneCanvas = {
  mounted() {
    this.sceneData = JSON.parse(this.el.dataset.scene || "{}");
    this.i18n = JSON.parse(this.el.dataset.i18n || "{}");
    this.currentTool = this.sceneData.can_edit ? "select" : "pan";
    this.editMode = this.sceneData.can_edit !== false;
    this.pendingSheetForPin = false;
    this.initCanvas();
  },

  destroyed() {
    if (this._keydownHandler) {
      document.removeEventListener("keydown", this._keydownHandler);
    }
    if (this.floatingToolbar) this.floatingToolbar.hide();
    if (this.ruler) this.ruler.destroy();
    if (this.minimap) this.minimap.destroy();
    if (this.contextMenu) this.contextMenu.destroy();
    if (this.layerHandler) this.layerHandler.destroy();
    if (this.connectionHandler) this.connectionHandler.destroy();
    if (this.annotationHandler) this.annotationHandler.destroy();
    if (this.pinHandler) this.pinHandler.destroy();
    if (this.zoneHandler) this.zoneHandler.destroy();

    if (this.leafletMap) {
      this.leafletMap.remove();
      this.leafletMap = null;
    }
  },

  initCanvas() {
    const { map, width, height } = initMap(this);
    this.leafletMap = map;
    this.canvasWidth = width;
    this.canvasHeight = height;

    // Initialize handlers (order matters: pins before connections, layers last)
    this.pinHandler = createPinHandler(this, this.i18n);
    this.pinHandler.init();

    this.zoneHandler = createZoneHandler(this, this.i18n);
    this.zoneHandler.init();

    this.connectionHandler = createConnectionHandler(this, this.i18n);
    this.connectionHandler.init();

    this.annotationHandler = createAnnotationHandler(this, this.i18n);
    this.annotationHandler.init();

    this.layerHandler = createLayerHandler(this);
    this.layerHandler.init();

    // Mini-map navigation
    this.minimap = createMinimap(this);
    this.minimap.init();

    // Ruler / distance measurement
    this.ruler = createRuler(this);

    // Context menu (shared across all handlers)
    this.contextMenu = createContextMenu(this);

    // Floating toolbar (positioned above selected element)
    this.floatingToolbar = createFloatingToolbar(this);
    // Expose on DOM element so the FloatingToolbar hook can access it
    this.el.__floatingToolbar = this.floatingToolbar;

    // Reposition toolbar on map move/zoom
    map.on("move", () => this.floatingToolbar?.reposition());
    map.on("zoom", () => this.floatingToolbar?.reposition());

    // Prevent browser context menu on canvas, show our own on empty canvas
    this.el.addEventListener("contextmenu", (e) => {
      e.preventDefault();
    });

    map.on("contextmenu", (e) => {
      if (!this.editMode) return;
      this.contextMenu.hide();

      const containerPoint = map.latLngToContainerPoint(e.latlng);
      const pos = { x: containerPoint.x, y: containerPoint.y };

      this.contextMenu.show(pos.x, pos.y, [
        {
          label: this.i18n.add_pin || "Add Pin Here",
          action: () => {
            const pct = this._toPercent(e.latlng);
            this.pushEvent("create_pin", { position_x: pct.x, position_y: pct.y });
          },
        },
        {
          label: this.i18n.add_annotation || "Add Annotation Here",
          action: () => {
            const pct = this._toPercent(e.latlng);
            this.pushEvent("create_annotation", { position_x: pct.x, position_y: pct.y });
          },
        },
      ]);
    });

    // Map click for deselection (when clicking empty canvas)
    map.on("click", (e) => {
      // Ignore clicks that originated from the floating toolbar or its popovers
      const toolbar = document.getElementById("floating-toolbar-content");
      if (toolbar && e.originalEvent && toolbar.contains(e.originalEvent.target)) return;

      // Only deselect if in select or pan mode (other tools use clicks for creation)
      if (this.currentTool === "select" || this.currentTool === "pan") {
        this.pushEvent("deselect", {});
        this.pinHandler.deselectAll();
        this.zoneHandler.deselectAll();
        this.connectionHandler.deselectAll();
        this.annotationHandler.deselectAll();
        this.floatingToolbar?.hide();
      }
    });

    // Wire tool changes from server
    this.handleEvent("tool_changed", ({ tool }) => {
      const prevTool = this.currentTool;
      // Cancel any in-progress drawing when switching tools
      if (this.isZoneTool(prevTool) && !this.isZoneTool(tool)) {
        this.zoneHandler.cancelDrawing();
      }
      if (prevTool === "connector" && tool !== "connector") {
        this.connectionHandler.cancelDrawing();
        this.connectionHandler.clearAllPinStates();
      }
      if (prevTool === "ruler" && tool !== "ruler") {
        this.ruler.clear();
      }
      this.currentTool = tool;
      this.updateCursor();
    });

    // Wire sheet-for-pin state from server
    this.handleEvent("pending_sheet_changed", ({ active }) => {
      this.pendingSheetForPin = active;
    });

    // Wire edit mode changes from server
    this.handleEvent("edit_mode_changed", ({ edit_mode }) => {
      this.editMode = edit_mode;
      if (!edit_mode) {
        this.zoneHandler.cancelDrawing();
        this.connectionHandler.cancelDrawing();
        this.connectionHandler.clearAllPinStates();
        this.ruler.clear();
        this.currentTool = "pan";
        this.floatingToolbar?.hide();
      }
      // Toggle dragging on existing elements
      this.pinHandler.setEditMode(edit_mode);
      this.annotationHandler.setEditMode(edit_mode);
      this.updateCursor();
    });

    // Wire element selection from server
    this.handleEvent("element_selected", ({ type, id }) => {
      // Clear all selections first
      this.pinHandler.deselectAll();
      this.zoneHandler.deselectAll();
      this.connectionHandler.deselectAll();
      this.annotationHandler.deselectAll();

      if (type === "pin") {
        this.pinHandler.selectPin(id);
      } else if (type === "zone") {
        this.zoneHandler.selectZone(id);
      } else if (type === "connection") {
        this.connectionHandler.selectConnection(id);
      } else if (type === "annotation") {
        this.annotationHandler.selectAnnotation(id);
      }

      // Show floating toolbar and close map settings panel
      this.floatingToolbar?.show(type, id);
      const settingsPanel = document.getElementById("map-settings-floating");
      if (settingsPanel) settingsPanel.classList.add("hidden");
    });

    this.handleEvent("element_deselected", () => {
      this.pinHandler.deselectAll();
      this.zoneHandler.deselectAll();
      this.connectionHandler.deselectAll();
      this.annotationHandler.deselectAll();
      this.floatingToolbar?.hide();
    });

    // Wire search highlight events
    this.handleEvent("highlight_elements", ({ elements }) => {
      // Dim all elements first
      this.pinHandler.setAllDimmed(true);
      this.zoneHandler.setAllDimmed(true);
      this.connectionHandler.setAllDimmed(true);
      this.annotationHandler.setAllDimmed(true);

      // Highlight matching elements
      for (const { type, id } of elements) {
        if (type === "pin") this.pinHandler.setDimmed(id, false);
        else if (type === "zone") this.zoneHandler.setDimmed(id, false);
        else if (type === "connection") this.connectionHandler.setDimmed(id, false);
        else if (type === "annotation") this.annotationHandler.setDimmed(id, false);
      }
    });

    this.handleEvent("clear_highlights", () => {
      this.pinHandler.clearDimming();
      this.zoneHandler.clearDimming();
      this.connectionHandler.clearDimming();
      this.annotationHandler.clearDimming();
    });

    this.handleEvent("focus_annotation_text", ({ id }) => {
      requestAnimationFrame(() => {
        const annId = id || this.annotationHandler?.selectedId;
        if (annId && this.annotationHandler?.enableInlineEditing) {
          const marker = this.annotationHandler.markers.get(annId);
          if (marker) this.annotationHandler.enableInlineEditing(marker);
        }
      });
    });

    this.handleEvent("focus_element", ({ type, id }) => {
      if (type === "pin") this.pinHandler.focusPin(id);
      else if (type === "zone") this.zoneHandler.focusZone(id);
      else if (type === "annotation") this.annotationHandler.focusAnnotation(id);
      // Connections span between pins — no single focus point
    });

    // Wire background image changes
    this.handleEvent("background_changed", ({ url }) => {
      // Remove existing background overlay or grid
      if (this.backgroundOverlay) {
        this.backgroundOverlay.remove();
        this.backgroundOverlay = null;
      }
      if (this.gridOverlay) {
        this.gridOverlay.remove();
        this.gridOverlay = null;
      }

      if (url) {
        // Load image to read natural dimensions, then fit canvas to them
        const img = new Image();
        img.onload = () => {
          const natW = img.naturalWidth || this.canvasWidth;
          const natH = img.naturalHeight || this.canvasHeight;
          const newBounds = imageBounds(natW, natH);

          this.canvasWidth = natW;
          this.canvasHeight = natH;
          this.initialBounds = newBounds;

          this.backgroundOverlay = L.imageOverlay(url, newBounds).addTo(this.leafletMap);
          this.backgroundOverlay.bringToBack();
          this.leafletMap.fitBounds(newBounds);

          // Reposition all elements to the new coordinate space
          if (this.pinHandler) this.pinHandler.repositionAll();
          if (this.zoneHandler) this.zoneHandler.repositionAll();
          if (this.connectionHandler) this.connectionHandler.repositionAll();
          if (this.annotationHandler) this.annotationHandler.repositionAll();

          if (this.minimap) this.minimap.refreshBackground();
        };
        img.src = url;
      } else {
        this.gridOverlay = addGridPlaceholder(this.leafletMap, this.canvasWidth, this.canvasHeight);
        if (this.minimap) this.minimap.refreshBackground();
      }
    });

    // Wire scene export
    this.handleEvent("export_scene", ({ format }) => {
      const name = this.sceneData.name || "scene";
      const safeName = name.replace(/[^a-zA-Z0-9_-]/g, "_");
      if (format === "svg") {
        exportSVG(this, safeName);
      } else {
        exportPNG(this, safeName);
      }
    });

    // Clipboard: store copied element data in localStorage
    this.handleEvent("element_copied", (data) => {
      localStorage.setItem("storyarn_scene_clipboard", JSON.stringify(data));
    });

    // Keyboard shortcuts
    this._keydownHandler = (e) => {
      if (!this.editMode) return;

      const mod = e.metaKey || e.ctrlKey;
      const inInput =
        e.target.tagName === "INPUT" ||
        e.target.tagName === "TEXTAREA" ||
        e.target.isContentEditable;

      // --- Modifier shortcuts (Cmd/Ctrl) ---
      if (mod) {
        // Undo: Cmd+Z
        if (e.key === "z" && !e.shiftKey) {
          e.preventDefault();
          this.pushEvent("undo", {});
          return;
        }
        // Redo: Cmd+Shift+Z or Cmd+Y
        if ((e.key === "z" && e.shiftKey) || e.key === "y") {
          e.preventDefault();
          this.pushEvent("redo", {});
          return;
        }
        // Duplicate: Cmd+Shift+D
        if (e.shiftKey && (e.key === "D" || e.key === "d")) {
          e.preventDefault();
          this.pushEvent("duplicate_selected", {});
          return;
        }
        // Copy: Cmd+Shift+C
        if (e.shiftKey && (e.key === "C" || e.key === "c")) {
          e.preventDefault();
          this.pushEvent("copy_selected", {});
          return;
        }
        // Paste: Cmd+Shift+V
        if (e.shiftKey && (e.key === "V" || e.key === "v")) {
          e.preventDefault();
          const raw = localStorage.getItem("storyarn_scene_clipboard");
          if (raw) {
            try {
              this.pushEvent("paste_element", JSON.parse(raw));
            } catch (_) {
              // ignore invalid clipboard data
            }
          }
          return;
        }
        return;
      }

      // --- Non-modifier shortcuts (skip when typing in inputs) ---
      if (inInput) return;

      // Delete/Backspace → delete selected element
      if (e.key === "Delete" || e.key === "Backspace") {
        e.preventDefault();
        this.pushEvent("delete_selected", {});
        return;
      }

      // Escape → deselect (zone/connection handlers catch Escape during drawing first)
      if (e.key === "Escape") {
        this.pushEvent("deselect", {});
        this.floatingToolbar?.hide();
        return;
      }

      // Tool shortcuts: Shift + letter (no Cmd/Ctrl)
      if (e.shiftKey && !e.altKey) {
        const toolMap = {
          V: "select",
          H: "pan",
          R: "rectangle",
          T: "triangle",
          C: "circle",
          F: "freeform",
          P: "pin",
          N: "annotation",
          L: "connector",
          M: "ruler",
        };
        const tool = toolMap[e.key];
        if (tool) {
          e.preventDefault();
          this.pushEvent("set_tool", { tool });
        }
      }
    };
    document.addEventListener("keydown", this._keydownHandler);

    // Apply initial tool state (disable dragging for select mode)
    this.updateCursor();
  },

  /** Converts a Leaflet LatLng to percentage coordinates. */
  _toPercent(latLng) {
    return toPercent(latLng, this.canvasWidth, this.canvasHeight);
  },

  /** Returns true if the given tool is a zone creation tool. */
  isZoneTool(tool) {
    return ["rectangle", "triangle", "circle", "freeform"].includes(tool);
  },

  updateCursor() {
    const container = this.el.querySelector("#scene-canvas-container");
    if (!container) return;

    const tool = this.currentTool;
    if (
      this.isZoneTool(tool) ||
      tool === "pin" ||
      tool === "connector" ||
      tool === "annotation" ||
      tool === "ruler"
    ) {
      container.style.cursor = "crosshair";
    } else if (tool === "pan") {
      container.style.cursor = "grab";
    } else {
      container.style.cursor = "";
    }

    // Figma-style: only pan mode allows map dragging
    if (this.leafletMap) {
      if (tool === "pan") {
        this.leafletMap.dragging.enable();
      } else {
        this.leafletMap.dragging.disable();
      }
    }
  },
};
