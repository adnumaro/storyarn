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

const flowFrontendSources = "^assets/app/(modules/flows|live/flow)/";
const flowSharedTechnicalPorts = [
  "^assets/app/components/ui/",
  "^assets/app/components/ConfirmDialog\\.vue$",
  "^assets/app/components/collab/CollabToast\\.vue$",
  "^assets/app/components/comments/",
  "^assets/app/components/dashboard/(DashboardDataTable|DashboardIssuesSection)\\.vue$",
  "^assets/app/components/dashboard/types\\.ts$",
  "^assets/app/components/forms/(BooleanToggle|EditableText|VariableCombobox)\\.vue$",
  "^assets/app/components/forms/assets/AssetPicker\\.vue$",
  "^assets/app/components/forms/fields/EntityCombobox\\.vue$",
  "^assets/app/components/health/(HealthStatusPopover\\.vue|health-details\\.ts)$",
  "^assets/app/components/toolbar/(ToolbarTooltip\\.vue|index\\.ts)$",
  "^assets/app/i18n\\.ts$",
  "^assets/app/plugins/expression-editor/theme\\.ts$",
  "^assets/app/shared/composables/(useColumnResize|useLive|useRemotePickerSearch|useUpload|useVerticalResize)\\.ts$",
  "^assets/app/shared/utils/date-utils\\.ts$",
  "^assets/app/shell/(DashboardContent|Sidebar|SidebarFrame)\\.vue$",
];
const flowModuleApprovedPorts = ["^assets/app/modules/flows/", ...flowSharedTechnicalPorts];
const flowLiveApprovedPorts = [
  "^assets/app/modules/flows/",
  "^assets/app/live/flow/",
  "^assets/app/shared/command-palette/registry\\.ts$",
  ...flowSharedTechnicalPorts,
];

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
    {
      name: "flows-no-cross-context-imports",
      comment:
        "Flows and its LiveVue adapter may compose technical UI, but must not import another product context.",
      severity: "error",
      from: {
        path: flowFrontendSources,
      },
      to: {
        path: "^assets/app/(modules/(?!flows/)|live/(?!flow/))",
      },
    },
    {
      name: "flows-module-not-to-live-adapter",
      comment:
        "The Flow LiveVue adapter may enter the Flow module; the Flow module must never depend back on its presentation adapter.",
      severity: "error",
      from: {
        path: "^assets/app/modules/flows/",
      },
      to: {
        path: "^assets/app/live/flow/",
      },
    },
    {
      name: "flows-module-not-to-global-coordinators",
      comment:
        "Application coordinators are wired by the Flow LiveVue adapter and injected through a narrow Flow-owned port.",
      severity: "error",
      from: {
        path: "^assets/app/modules/flows/",
      },
      to: {
        path: "^assets/app/shared/command-palette/registry\\.ts$",
      },
    },
    {
      name: "flows-module-only-approved-frontend-ports",
      comment:
        "Flow module dependencies are fail-closed. New external imports require an explicit decision that they are technical presentation or infrastructure ports.",
      severity: "error",
      from: {
        path: "^assets/app/modules/flows/",
      },
      to: {
        path: "^assets/app/",
        pathNot: flowModuleApprovedPorts,
      },
    },
    {
      name: "flows-live-adapter-only-approved-frontend-ports",
      comment:
        "The Flow LiveVue adapter is fail-closed and may additionally wire the explicit application coordinator port.",
      severity: "error",
      from: {
        path: "^assets/app/live/flow/",
      },
      to: {
        path: "^assets/app/",
        pathNot: flowLiveApprovedPorts,
      },
    },
    {
      name: "flows-no-shared-business-rules",
      comment:
        "Flow expression, versioning and asset-value semantics are Flow-owned. Shared imports here would silently re-couple the bounded context.",
      severity: "error",
      from: {
        path: flowFrontendSources,
      },
      to: {
        path: "^assets/app/(shared/domain/|shared/types/health\\.ts$|shared/composables/useCodeEditor\\.ts$|components/builders/|components/forms/ExpressionEditor\\.vue$|components/forms/assets/(AudioAsset|ImageAsset|ImageFit|ImagePosition)\\.vue$|components/versioning/|plugins/expression-editor/(?!theme\\.ts$))",
      },
    },
    {
      name: "no-frontend-imports-into-flows",
      comment:
        "Only the Flow LiveVue adapter may enter Flow internals. Other contexts and shared code need an explicit public contract instead.",
      severity: "error",
      from: {
        path: "^assets/app/(?!modules/flows/|live/flow/|test/)",
      },
      to: {
        path: "^assets/app/modules/flows/",
      },
    },
    {
      name: "flow-tests-owned-by-flow",
      comment:
        "Only Flow-owned tests may import Flow frontend internals. Cross-context tests must exercise a public boundary instead.",
      severity: "error",
      from: {
        path: "^assets/app/test/(?!modules/flows(?:/|$)|live/flow(?:/|$))",
      },
      to: {
        path: "^assets/app/(modules/flows|live/flow)/",
      },
    },
    ...crossModuleRules,
  ],
  options: {
    // Architecture boundaries include compile-time coupling. Without this,
    // dependency-cruiser drops `import type` edges and a context can bypass
    // every rule by importing another context's models as types only.
    tsPreCompilationDeps: "specify",
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
