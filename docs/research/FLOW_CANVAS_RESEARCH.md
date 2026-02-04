# Flow Canvas Research: Shadow DOM vs Light DOM

> **Context:** Custom node rendering for Rete.js flow editor with Tailwind/daisyUI theming.

## Problem Statement

We need to render custom nodes in Rete.js that:
1. Support Tailwind CSS and daisyUI theming (dark/light mode)
2. Display Lucide icons
3. Have working connection points (sockets) for node connections

## Shadow DOM vs Light DOM

### Shadow DOM

**Advantages:**
- **Style encapsulation**: Styles don't leak in or out
- **DOM encapsulation**: Internal elements hidden from `querySelectorAll`
- **Slots work natively**: `<slot>` elements project content correctly
- **Isolation**: Components are protected from external CSS/JS

**Disadvantages:**
- **Global styles don't work**: Tailwind classes, daisyUI themes won't apply
- **CSS custom properties required**: Must use `var(--property)` for theming
- **Accessibility issues**: ARIA references broken across shadow boundaries
- **Form integration problems**: Form elements don't associate with parent forms
- **Debugging complexity**: `document.activeElement` returns host, not focused element
- **Inherited properties leak**: Some CSS properties still inherit through

### Light DOM

**Advantages:**
- **Global styles work**: Tailwind, daisyUI, any external CSS applies
- **Better accessibility**: IDs, `aria-labelledby`, `for` attributes work
- **Simpler debugging**: Standard DOM inspection
- **No JavaScript dependency for rendering**: HTML renders immediately

**Disadvantages:**
- **No style encapsulation**: Class names can conflict with global styles
- **DOM exposed**: Internal elements accessible via `querySelectorAll`
- **SLOTS DON'T WORK**: `<slot>` is a Shadow DOM feature only

## The Rete.js Socket Problem

### How Rete.js Renders Sockets

From the [Lit plugin source code](https://github.com/retejs/lit-plugin):

```typescript
// node.ts - Sockets rendered via rete-ref with positioning
<rete-ref
  .data=${{ type: 'socket', side: 'output', key, nodeId, payload: output.socket }}
  .emit=${emit}
  style="margin-right: calc(0px - var(--socket-size) / 2 - var(--socket-margin))"
>
</rete-ref>
```

The `rete-ref` component:
1. Registers socket position with the connection plugin
2. Renders the socket element inside
3. Uses DOM positioning for connection line calculation

### Why Light DOM Breaks Connections

In our Light DOM implementation:
```html
<slot name="input-socket-${key}"></slot>  <!-- DOESN'T WORK! -->
```

**Problem**: Slots only work in Shadow DOM. Without them, Rete.js can't:
- Project socket components into our custom node
- Track socket positions for drawing connections
- Handle socket interactions (hover, click to connect)

## Solutions

### Option 1: Shadow DOM + CSS Custom Properties (Recommended)

Keep Shadow DOM for proper socket functionality, use CSS custom properties for theming.

```typescript
class StoryarnNode extends LitElement {
  // Keep Shadow DOM (default)

  static styles = css`
    .node {
      background: var(--node-bg, oklch(var(--b1)));
      color: var(--node-text, oklch(var(--bc)));
    }
  `;
}
```

**Pros:**
- Sockets work correctly
- Connections work correctly
- daisyUI CSS variables like `--b1`, `--bc` pierce Shadow DOM

**Cons:**
- Can't use Tailwind utility classes directly
- Need to define all styles in component

### Option 2: Shadow DOM + Adopted Stylesheets

Import Tailwind styles into the Shadow DOM.

```typescript
class StoryarnNode extends LitElement {
  connectedCallback() {
    super.connectedCallback();
    // Adopt document stylesheets
    if (this.shadowRoot) {
      this.shadowRoot.adoptedStyleSheets = [
        ...document.adoptedStyleSheets,
        // Or create from Tailwind output
      ];
    }
  }
}
```

**Pros:**
- Tailwind classes might work
- Sockets work

**Cons:**
- Complex setup
- Performance implications
- May not work with all styles

### Option 3: Light DOM + Manual Socket Rendering

Render sockets directly without slots, manually handle positioning.

```typescript
class StoryarnNode extends LitElement {
  createRenderRoot() { return this; }

  render() {
    return html`
      <div class="flow-node">
        <!-- Render sockets directly, not via slots -->
        ${this.renderSockets()}
      </div>
    `;
  }

  renderSockets() {
    // Manually create and position socket elements
    // Register with rete-render-utils for position tracking
  }
}
```

**Pros:**
- Tailwind works fully

**Cons:**
- Complex implementation
- Need to handle all socket logic manually
- May break connection plugin expectations

### Option 4: Hybrid - Light DOM Node, Shadow DOM Sockets

Use Light DOM for the node container, Shadow DOM for socket wrappers.

**Pros:**
- Best of both worlds potentially

**Cons:**
- Increased complexity
- Nested shadow roots

## Recommendation

**Use Option 1: Shadow DOM + CSS Custom Properties**

Reasons:
1. daisyUI's CSS variables (`--b1`, `--bc`, `--p`, etc.) already pierce Shadow DOM
2. Sockets and connections work out of the box
3. Less custom code to maintain
4. Dark/light mode works via CSS variables

Implementation approach:
1. Keep Shadow DOM (remove `createRenderRoot`)
2. Use daisyUI CSS variables for colors: `oklch(var(--b1))`
3. Define Tailwind-equivalent styles using CSS custom properties
4. Use Lucide icons via `createElement` + `unsafeSVG`

## Icons in Shadow DOM

**Lucide icons work perfectly in Shadow DOM** because SVG is self-contained.

### Implementation

```javascript
import { createElement, MessageSquare } from "lucide";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";

// Create icon with direct attributes (not Tailwind classes)
const iconElement = createElement(MessageSquare, {
  width: 16,
  height: 16,
  stroke: "currentColor",  // Inherits from parent color
  "stroke-width": 2
});

// Convert to string for Lit template
const iconSvg = iconElement.outerHTML;

// In render()
return html`<span>${unsafeSVG(iconSvg)}</span>`;
```

### Why It Works

| Aspect                 | Works in Shadow DOM?   | Reason                            |
|------------------------|------------------------|-----------------------------------|
| SVG element            | ✅ Yes                  | Self-contained, no external deps  |
| `width`/`height` attrs | ✅ Yes                  | Native SVG attributes             |
| `stroke: currentColor` | ✅ Yes                  | `color` is inherited CSS property |
| Tailwind classes       | ❌ No                   | External styles don't penetrate   |

### Key Difference from Light DOM

```javascript
// Light DOM - Tailwind classes work
createElement(Icon, { class: "size-4 text-white" })

// Shadow DOM - Use direct attributes
createElement(Icon, { width: 16, height: 16, stroke: "currentColor" })
```

## Design Decisions (Based on articy:draft & Arcweave)

### Sockets/Pins
- **Size**: 12px diameter (small, subtle circles)
- **Color**: Muted, matches theme (`oklch(var(--bc) / 0.3)`)
- **Border**: 2px solid, slightly more visible
- **Hover**: Highlights with primary color, slight scale up

### Connections
- **Style**: Bezier curves (smooth)
- **Stroke**: 2px, muted color
- **Hover**: Primary color, 3px stroke

### Background
- **Color**: `oklch(var(--b2))` - slightly darker than nodes
- **Grid**: Subtle dot pattern (20px spacing)

### Nodes
- **Background**: `oklch(var(--b1))` - base color
- **Border**: 1.5px, color matches header at 25% opacity
- **Header**: Solid color per node type
- **Shadow**: Subtle drop shadow

### Minimap
- **Position**: Bottom-right corner
- **Size**: 180x120px
- **Background**: Semi-transparent with blur

## Sources

- [Shadow DOM Pros and Cons - Manuel Matuzovic](https://www.matuzo.at/blog/2023/pros-and-cons-of-shadow-dom/)
- [Light-DOM-Only Web Components - Frontend Masters](https://frontendmasters.com/blog/light-dom-only/)
- [Rete.js Lit Plugin Documentation](https://retejs.org/docs/guides/renderers/lit/)
- [Rete.js Connections Guide](https://retejs.org/docs/guides/connections/)
- [Lit Component Composition](https://lit.dev/docs/composition/component-composition/)
- [Lit Shadow DOM Documentation](https://lit.dev/docs/components/shadow-dom/)
- [rete-render-utils npm](https://www.npmjs.com/package/rete-render-utils)
