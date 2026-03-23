/**
 * App V2 — Vue + NuxtUI entry point.
 *
 * Used exclusively by v2 pages (scene editor v2, sheet editor v2, etc.)
 * Loaded via Vite dev server in dev, built to static assets in prod.
 * Completely separate from app.js (v1, esbuild + DaisyUI).
 */

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { getHooks } from "live_vue"
import liveVueApp from "../vue"
import topbar from "topbar"

// V1 hooks needed by scene canvas (Leaflet-based, framework-independent)
import { CanvasDropZone } from "./hooks/canvas_drop_zone"
import { CanvasToolbar } from "./hooks/canvas_toolbar"
import { RightSidebar } from "./hooks/right_sidebar"
import { SceneCanvas } from "./hooks/scene_canvas"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    ...getHooks(liveVueApp),
    CanvasDropZone,
    CanvasToolbar,
    RightSidebar,
    SceneCanvas,
  },
})

// Progress bar
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()

window.liveSocket = liveSocket

// Theme sync — reads same localStorage key as v1 ("phx:theme"), applies as class
function applyV2Theme() {
  const stored = localStorage.getItem("phx:theme")
  const dark = stored ? stored === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches
  document.documentElement.classList.toggle("dark", dark)
}
applyV2Theme()
window.addEventListener("storage", (e) => { if (e.key === "phx:theme") applyV2Theme() })
window.addEventListener("phx:set-theme", applyV2Theme)

// Dev tools
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", (e) => (keyDown = e.key))
    window.addEventListener("keyup", () => (keyDown = null))
    window.addEventListener(
      "click",
      (e) => {
        if (keyDown === "c") {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtCaller(e.target)
        } else if (keyDown === "d") {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtDef(e.target)
        }
      },
      true,
    )

    window.liveReloader = reloader
  })
}
