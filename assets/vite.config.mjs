import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { templateCompilerOptions } from "@tresjs/core";
import tailwindcss from "@tailwindcss/vite";
import liveVuePlugin from "live_vue/vitePlugin";
import path from "path";

export default defineConfig({
  root: ".",
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:4000" },
    fs: { allow: [".."] },
  },
  optimizeDeps: {
    include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"],
  },
  ssr: { noExternal: process.env.NODE_ENV === "production" ? true : undefined },
  build: {
    manifest: false,
    ssrManifest: false,
    rollupOptions: {
      input: ["js/app.js", "css/app.css"],
    },
    outDir: "../priv/static",
    emptyOutDir: false,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
      "@app": path.resolve(__dirname, "app"),
      "@components": path.resolve(__dirname, "app", "components"),
      "@composables": path.resolve(__dirname, "app", "composables"),
      "@utils": path.resolve(__dirname, "app", "utils"),
      "@modules": path.resolve(__dirname, "app", "modules"),
      "@plugins": path.resolve(__dirname, "app", "plugins"),
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
    modules: [path.resolve(__dirname, ".."), "node_modules"],
  },
  plugins: [
    tailwindcss(),
    vue({
      template: {
        compilerOptions: {
          isCustomElement: (tag) =>
            tag.startsWith("hex-") ||
            templateCompilerOptions.template.compilerOptions.isCustomElement(tag),
        },
      },
    }),
    liveVuePlugin(),
  ],
});
