/**
 * wrap() — exposes a real Vue component as a React component.
 *
 * The design runtime renders React (host React/ReactDOM come from the page
 * globals; this bundle never ships its own copy). Each wrapped instance:
 *   - mounts a per-instance Vue app (with i18n + live stub, see host.ts)
 *     into a `display: contents` host div, so layout is transparent;
 *   - mirrors React props into a Vue `reactive` object every render
 *     (className → class; style passed through to the Vue root; `on*`
 *     callbacks become Vue emit listeners via Vue's own h() convention);
 *   - renders React children into the component's default slot — and any
 *     prop named in `contentSlots` into the same-named Vue slot — through
 *     `display: contents` placeholders targeted with ReactDOM.createPortal.
 *     Portals work even when reka-ui teleports the placeholder to <body>.
 */
import {
  createApp,
  effectScope,
  h,
  reactive,
  ref,
  watchEffect,
  type App,
  type Component,
} from "vue";
import { installHost, type DsTheme } from "./host";

export interface WrapOptions {
  /** Rename React-side props to Vue-side ones, e.g. { value: "modelValue", onChange: "onUpdate:modelValue" }. */
  propAliases?: Record<string, string>;
  /** React props whose ReactNode value renders into the same-named Vue slot. */
  contentSlots?: string[];
}

interface AnyProps {
  [key: string]: unknown;
}

interface VueHandle {
  app: App;
  state: { props: AnyProps; slots: string[] };
  stopScope: () => void;
}

declare global {
  interface Window {
    React: any;
    ReactDOM: any;
  }
}

function mapProps(raw: AnyProps, opts: WrapOptions): AnyProps {
  const skip = new Set(["children", ...(opts.contentSlots ?? [])]);
  const aliases = opts.propAliases ?? {};
  const out: AnyProps = {};
  for (const key of Object.keys(raw)) {
    if (skip.has(key)) continue;
    if (key === "className") {
      out.class = raw[key];
      continue;
    }
    out[aliases[key] ?? key] = raw[key];
  }
  return out;
}

export function wrap(name: string, VueComp: Component, opts: WrapOptions = {}) {
  function Wrapped(props: AnyProps) {
    const React = window.React;
    const ReactDOM = window.ReactDOM;
    const hostRef = React.useRef(null);
    const vueRef = React.useRef(null as VueHandle | null);
    const [slotEls, setSlotEls] = React.useState({} as Record<string, Element>);

    const mapped = mapProps(props, opts);
    const wantedSlots: string[] = [];
    if (props.children != null) wantedSlots.push("default");
    for (const s of opts.contentSlots ?? []) {
      if (props[s] != null) wantedSlots.push(s);
    }

    React.useEffect(() => {
      const state = reactive({ props: { ...mapped }, slots: [...wantedSlots] });
      const slotRegistry = reactive({} as Record<string, Element>);
      const theme: DsTheme = { isDark: ref(false) };

      const app = createApp({
        render() {
          const slots: Record<string, () => unknown> = {};
          for (const s of state.slots) {
            slots[s] = () =>
              h("div", {
                style: "display: contents",
                "data-ds-slot": s,
                ref: (el: Element | null) => {
                  if (el) slotRegistry[s] = el;
                  else delete slotRegistry[s];
                },
              });
          }
          return h(VueComp, { ...state.props }, slots);
        },
      });
      installHost(app, theme);
      app.mount(hostRef.current);

      const host: HTMLElement = hostRef.current;
      theme.isDark.value = host.closest(".dark") != null;

      const scope = effectScope();
      scope.run(() => {
        watchEffect(
          () => {
            setSlotEls({ ...slotRegistry });
          },
          { flush: "post" },
        );
      });

      vueRef.current = { app, state, stopScope: () => scope.stop() };
      return () => {
        vueRef.current = null;
        scope.stop();
        app.unmount();
      };
    }, []);

    // Mirror the latest React props/slot set into Vue on every render.
    React.useEffect(() => {
      const vm = vueRef.current;
      if (!vm) return;
      for (const k of Object.keys(vm.state.props)) {
        if (!(k in mapped)) delete vm.state.props[k];
      }
      Object.assign(vm.state.props, mapped);
      if (
        vm.state.slots.length !== wantedSlots.length ||
        vm.state.slots.some((s, i) => s !== wantedSlots[i])
      ) {
        vm.state.slots = [...wantedSlots];
      }
    });

    const portals = [];
    for (const s of wantedSlots) {
      const el = slotEls[s];
      if (el && el.isConnected) {
        portals.push(
          ReactDOM.createPortal(s === "default" ? props.children : props[s], el, `ds-slot-${s}`),
        );
      }
    }

    return React.createElement(
      "div",
      { ref: hostRef, style: { display: "contents" }, "data-ds-component": name },
      ...portals,
    );
  }
  (Wrapped as { displayName?: string }).displayName = name;
  return Wrapped;
}
