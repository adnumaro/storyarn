import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import liveVuePlugin from "live_vue/vitePlugin";
import path from "path";

export default defineConfig({
  root: ".",
  server: {
    host: "localhost",
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:4000" },
    fs: { allow: [".."] },
  },
  optimizeDeps: {
    include: ["phoenix", "phoenix_html", "phoenix_live_view"],
    exclude: ["live_vue"],
  },
  ssr: { noExternal: process.env.NODE_ENV === "production" ? true : undefined },
  build: {
    manifest: true,
    ssrManifest: false,
    rollupOptions: {
      input: ["assets/js/app.js", "assets/css/app.css"],
    },
    outDir: "priv/static",
    emptyOutDir: false,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "assets"),
      "@app": path.resolve(__dirname, "assets", "app"),
      "@components": path.resolve(__dirname, "assets", "app", "components"),
      "@shared": path.resolve(__dirname, "assets", "app", "shared"),
      "@modules": path.resolve(__dirname, "assets", "app", "modules"),
      "@shell": path.resolve(__dirname, "assets", "app", "shell"),
      "@plugins": path.resolve(__dirname, "assets", "app", "plugins"),
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
    modules: [path.resolve(__dirname), "node_modules"],
  },
  plugins: [
    tailwindcss(),
    vue({
      template: {
        compilerOptions: {
          isCustomElement: (tag) => tag.startsWith("hex-"),
        },
      },
    }),
    liveVuePlugin(),
  ],
});
