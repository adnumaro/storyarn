import { h } from "vue"
import { createLiveVue, findComponent } from "live_vue"

export default createLiveVue({
  resolve: (name) => {
    const components = {
      ...import.meta.glob("./**/*.vue", { eager: true }),
      ...import.meta.glob("../../lib/**/*.vue", { eager: true }),
    }
    return findComponent(components, name)
  },
  setup: ({ createApp, component, props, slots, plugin, el }) => {
    const app = createApp({ render: () => h(component, props, slots) })
    app.use(plugin)
    app.mount(el)
    return app
  },
})
