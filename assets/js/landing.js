/**
 * Landing page entry point — only loaded on the public landing page.
 * Keeps Three.js + GSAP out of the main app.js bundle.
 */

import "./landing_page/portal";
import "./landing_page/scroll_animation";
import "./landing_page/section_scroll";
// import "./landing_page/section_pager"; // DISABLED — auto-scroll broken for non-feature sections
import "./landing_page/animations";
import "./landing_page/discover_section";
