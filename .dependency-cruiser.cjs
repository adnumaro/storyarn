const productModules = [
  "account",
  "assets",
  "auth",
  "docs",
  "flows",
  "localization",
  "projects",
  "public",
  "scenes",
  "sheets",
  "workspaces",
];

const crossModuleRules = productModules.map((moduleName) => ({
  name: `module-${moduleName}-no-cross-internals`,
  comment:
    "Modules should not import another module's internals. Export a public API from index.ts or a dedicated navigation entrypoint instead.",
  severity: "warn",
  from: {
    path: `^assets/app/modules/${moduleName}/`,
  },
  to: {
    path: `^assets/app/modules/(?!${moduleName}/)`,
    pathNot: [
      "^assets/app/modules/[^/]+/index\\.ts$",
      "^assets/app/modules/[^/]+/navigation(/|\\.ts$)",
    ],
  },
}));

module.exports = {
  forbidden: [
    {
      name: "not-to-unresolvable",
      comment: "Imports must resolve through Vite/TypeScript aliases or relative paths.",
      severity: "error",
      from: {},
      to: {
        couldNotResolve: true,
      },
    },
    {
      name: "no-circular",
      comment: "Circular dependencies make frontend module boundaries hard to reason about.",
      // Start as a warning during the folder migration. Promote to "error"
      // once existing barrel/component cycles are removed or intentionally
      // exempted.
      severity: "warn",
      from: {},
      to: {
        circular: true,
      },
    },
    {
      name: "not-to-test",
      comment: "Production frontend code must not import test helpers or specs.",
      severity: "error",
      from: {
        path: "^assets/app/(?!test/)",
      },
      to: {
        path: "^assets/app/test/",
      },
    },
    {
      name: "ui-not-to-product-code",
      comment: "Design-system primitives must stay product-agnostic.",
      severity: "error",
      from: {
        path: "^assets/app/components/ui/",
      },
      to: {
        path: "^assets/app/(modules|plugins|composables/)",
      },
    },
    {
      name: "shared-domain-not-to-ui-or-live",
      comment: "Shared domain code must remain pure and not depend on Vue UI or LiveView wiring.",
      severity: "error",
      from: {
        path: "^assets/app/shared/domain/",
      },
      to: {
        path: "^assets/app/(components|shared/composables/useLive|modules/)",
      },
    },
    {
      name: "shared-components-not-to-product-modules",
      comment:
        "Reusable components should not import product-module internals. Move product-specific code into modules.",
      severity: "warn",
      from: {
        path: "^assets/app/components/(?!layout/)",
      },
      to: {
        path: "^assets/app/modules/",
      },
    },
    {
      name: "shell-not-to-module-internals",
      comment:
        "The app shell should only depend on public module APIs or navigation entrypoints, not module internals.",
      severity: "error",
      from: {
        path: "^assets/app/(shell|components/layout)/",
      },
      to: {
        path: "^assets/app/modules/",
        pathNot: [
          "^assets/app/modules/[^/]+/index\\.ts$",
          "^assets/app/modules/[^/]+/navigation(/|\\.ts$)",
        ],
      },
    },
    ...crossModuleRules,
  ],
  options: {
    tsConfig: {
      fileName: "tsconfig.json",
    },
    doNotFollow: {
      path: "node_modules|deps|priv|_build|cover",
    },
    enhancedResolveOptions: {
      extensions: [".js", ".mjs", ".ts", ".tsx", ".vue", ".json"],
      exportsFields: ["exports"],
      conditionNames: ["import", "require", "node", "default"],
      mainFields: ["module", "jsnext:main", "main", "types", "typings"],
    },
  },
};
