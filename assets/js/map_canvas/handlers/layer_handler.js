/**
 * Layer handler factory for the map canvas.
 *
 * Manages layer visibility toggling on the Leaflet canvas.
 * When a layer is hidden, its pins, zones, and related connections disappear.
 * Elements with layer_id: null are always visible.
 *
 * Also manages Fog of War overlays: when a layer has fog_enabled,
 * a dark overlay covers the canvas with holes cut out for zones on that layer.
 */

import L from "leaflet";

/**
 * Creates the layer handler attached to the hook instance.
 * @param {Object} hook - The MapCanvas hook instance
 * @returns {{ init(), destroy(), applyVisibility(layers), rebuildFog() }}
 */
export function createLayerHandler(hook) {
  // Set of hidden layer IDs
  const hiddenLayers = new Set();

  // Map of layer ID → fog overlay L.Polygon
  const fogOverlays = new Map();

  // Fog layer group — rendered above all other layers
  let fogLayerGroup = null;

  function init() {
    // Initialize hidden layers from initial data
    const layers = hook.mapData.layers || [];
    for (const layer of layers) {
      if (!layer.visible) {
        hiddenLayers.add(layer.id);
      }
    }

    // Create fog layer group (on top of everything)
    fogLayerGroup = L.layerGroup().addTo(hook.leafletMap);

    // Apply initial visibility
    applyVisibility();

    // Build initial fog overlays
    rebuildFog();

    wireServerEvents();
  }

  function destroy() {
    hiddenLayers.clear();
    clearAllFog();
    if (fogLayerGroup) {
      fogLayerGroup.remove();
      fogLayerGroup = null;
    }
  }

  /** Wires handleEvent listeners from the server. */
  function wireServerEvents() {
    hook.handleEvent("layer_visibility_changed", ({ id, visible }) => {
      if (visible) {
        hiddenLayers.delete(id);
      } else {
        hiddenLayers.add(id);
      }
      applyVisibility();
      rebuildFog();
    });

    hook.handleEvent("layer_deleted", ({ id }) => {
      hiddenLayers.delete(id);
      rebuildFog();
      applyVisibility();
    });

    hook.handleEvent("layer_fog_changed", ({ id, fog_enabled, fog_color, fog_opacity }) => {
      // Update the layer data in mapData
      const layers = hook.mapData.layers || [];
      const layer = layers.find((l) => l.id === id);
      if (layer) {
        layer.fog_enabled = fog_enabled;
        layer.fog_color = fog_color;
        layer.fog_opacity = fog_opacity;
      }
      rebuildFog();
      applyVisibility();
    });
  }

  /**
   * Shows/hides elements based on layer visibility and fog.
   *
   * Layer hidden → element hidden.
   * Fog active on a layer → only elements ON that layer are visible;
   * elements on other layers (or with no layer) are hidden under the fog.
   */
  function applyVisibility() {
    // Collect IDs of visible layers that have fog enabled
    const layers = hook.mapData.layers || [];
    const fogLayerIds = new Set();
    for (const layer of layers) {
      if (layer.fog_enabled && !hiddenLayers.has(layer.id)) {
        fogLayerIds.add(layer.id);
      }
    }
    const hasFog = fogLayerIds.size > 0;

    // Pins
    for (const [_pinId, marker] of hook.pinHandler.markers) {
      const pin = marker.pinData;
      const shouldHide = isElementHidden(pin.layer_id, hasFog, fogLayerIds);
      toggleLayer(hook.pinLayer, marker, shouldHide);
    }

    // Zones
    for (const [_zoneId, polygon] of hook.zoneHandler.polygons) {
      const zone = polygon.zoneData;
      const shouldHide = isElementHidden(zone.layer_id, hasFog, fogLayerIds);
      toggleLayer(hook.zoneLayer, polygon, shouldHide);
    }

    // Annotations
    if (hook.annotationHandler) {
      for (const [_annId, marker] of hook.annotationHandler.markers) {
        const ann = marker.annotationData;
        const shouldHide = isElementHidden(ann.layer_id, hasFog, fogLayerIds);
        toggleLayer(hook.annotationLayer, marker, shouldHide);
      }
    }

    // Connections: hide if either pin is hidden
    for (const [_connId, line] of hook.connectionHandler.lines) {
      const conn = line.connData;
      const fromHidden = isPinHidden(conn.from_pin_id);
      const toHidden = isPinHidden(conn.to_pin_id);
      toggleLayer(hook.connectionLayer, line, fromHidden || toHidden);
    }
  }

  /**
   * Determines if an element should be hidden based on its layer_id,
   * layer visibility, and fog state.
   */
  function isElementHidden(layerId, hasFog, fogLayerIds) {
    // Element's own layer is hidden
    if (layerId && hiddenLayers.has(layerId)) return true;
    // Fog is active — only elements on a fogged layer are visible
    if (hasFog && (!layerId || !fogLayerIds.has(layerId))) return true;
    return false;
  }

  /** Adds or removes a leaflet object from a layer group. */
  function toggleLayer(layerGroup, obj, shouldHide) {
    if (shouldHide) {
      if (layerGroup.hasLayer(obj)) layerGroup.removeLayer(obj);
    } else {
      if (!layerGroup.hasLayer(obj)) layerGroup.addLayer(obj);
    }
  }

  // ---------------------------------------------------------------------------
  // Fog of War
  // ---------------------------------------------------------------------------

  /**
   * Rebuilds the fog overlay.
   * Multiple fogged layers merge into a single dark overlay.
   * Zones from ALL fogged layers cut holes in the fog.
   */
  function rebuildFog() {
    clearAllFog();

    const layers = hook.mapData.layers || [];
    const fogLayers = layers.filter((l) => l.fog_enabled && !hiddenLayers.has(l.id));

    if (fogLayers.length === 0) return;

    const w = hook.canvasWidth;
    const h = hook.canvasHeight;

    // Outer ring — covers entire canvas (with padding to avoid edge gaps)
    const pad = Math.max(w, h) * 0.1;
    const outerRing = [
      [pad, -pad],
      [pad, w + pad],
      [-(h + pad), w + pad],
      [-(h + pad), -pad],
    ];

    // Collect fog layer IDs for hole matching
    const fogLayerIds = new Set(fogLayers.map((l) => l.id));

    // Collect holes from zones on ANY fogged layer
    const holes = [];
    for (const [_zoneId, polygon] of hook.zoneHandler.polygons) {
      const zone = polygon.zoneData;
      if (zone.layer_id && fogLayerIds.has(zone.layer_id)) {
        const latLngs = polygon.getLatLngs();
        if (latLngs?.[0]) {
          const ring = Array.isArray(latLngs[0][0]) ? latLngs[0] : latLngs[0];
          holes.push(ring.map((ll) => [ll.lat, ll.lng]));
        }
      }
    }

    // Use fog settings from the first fogged layer
    const primary = fogLayers[0];
    const fogPolygon = L.polygon([outerRing, ...holes], {
      color: "transparent",
      fillColor: primary.fog_color || "#000000",
      fillOpacity: primary.fog_opacity ?? 0.85,
      interactive: false,
      pane: "fogPane",
    });

    fogPolygon.addTo(fogLayerGroup);
    fogOverlays.set("merged", fogPolygon);
  }

  /** Clears all fog overlays. */
  function clearAllFog() {
    for (const overlay of fogOverlays.values()) {
      overlay.remove();
    }
    fogOverlays.clear();
  }

  /** Checks if a pin is currently hidden (layer hidden or under fog). */
  function isPinHidden(pinId) {
    const marker = hook.pinHandler.markers.get(pinId);
    if (!marker) return false;
    return !hook.pinLayer.hasLayer(marker);
  }

  /** Returns whether a specific layer is currently hidden. */
  function isLayerHidden(layerId) {
    return hiddenLayers.has(layerId);
  }

  return {
    init,
    destroy,
    applyVisibility,
    isLayerHidden,
    rebuildFog,
  };
}
