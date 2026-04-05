import { createLiveVue, findComponent } from "live_vue";
import { h } from "vue";
import VueKonva from "vue-konva";
import { i18n } from "./i18n.js";

let appCounter = 0;

export default createLiveVue({
  resolve: (name) => {
    const components = {
      ...import.meta.glob("./**/*.vue", { eager: true }),
      ...import.meta.glob("../../lib/**/*.vue", { eager: true }),
    };
    return findComponent(components, name);
  },
  setup: ({ createApp, component, props, slots, plugin, el }) => {
    const app = createApp({ render: () => h(component, props, slots) });
    app.config.idPrefix = `vue-${appCounter++}`;
    // Suppress vue-konva false-positive warnings about event listeners on v-group/v-layer
    // vue-konva handles Konva events internally via .on() — Vue's attribute inheritance doesn't apply
    const origWarn = app.config.warnHandler;
    app.config.warnHandler = (msg, vm, trace) => {
      if (msg.includes("Extraneous non-emits event listeners")) return;
      if (origWarn) origWarn(msg, vm, trace);
      else console.warn(`[Vue warn]: ${msg}${trace}`);
    };
    app.use(plugin);
    app.use(VueKonva);
    app.use(i18n);
    app.mount(el);
    return app;
  },
});
