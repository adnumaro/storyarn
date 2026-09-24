import { defineConfig, mergeConfig } from "vitest/config";
import viteConfig from "./vite.config.mjs";

// live_vue's dev-server hook exits the process when stdin closes, as it does on CI runners.
const plugins = viteConfig.plugins.filter((plugin) => plugin?.name !== "live-vue");

export default mergeConfig(
  { ...viteConfig, plugins },
  defineConfig({
    test: {
      environment: "jsdom",
      include: ["assets/app/test/**/*.test.ts"],
      setupFiles: ["assets/app/test/setup.ts"],
      globals: true,
    },
  }),
);
