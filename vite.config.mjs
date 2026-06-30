import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import liveVuePlugin from "live_vue/vitePlugin";
import path from "path";

const vendorChunkRules = [
  ["vendor-tiptap", ["@tiptap", "prosemirror"]],
  ["vendor-codemirror", ["@codemirror", "@lezer"]],
  ["vendor-flow-layout", ["elkjs"]],
  ["vendor-flow-vue", ["rete-vue-plugin"]],
  ["vendor-flow-area", ["rete-area-plugin", "rete-render-utils"]],
  [
    "vendor-flow-plugins",
    [
      "rete-connection-plugin",
      "rete-context-menu-plugin",
      "rete-history-plugin",
      "rete-minimap-plugin",
    ],
  ],
  ["vendor-flow-core", ["/node_modules/rete/"]],
  ["vendor-canvas", ["konva", "vue-konva", "modern-screenshot"]],
  ["vendor-analytics", ["posthog-js"]],
  ["vendor-vue", ["vue", "live_vue"]],
];

const vendorChunkFor = (id) => {
  if (!id.includes("node_modules")) return;

  return (
    vendorChunkRules.find(([, matches]) => matches.some((match) => id.includes(match)))?.[0] ??
    "vendor"
  );
};

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
      output: {
        manualChunks: vendorChunkFor,
      },
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
