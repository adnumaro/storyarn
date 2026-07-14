let publicRoutePreload;

export function preloadPublicRouteTargets() {
  if (!document.getElementById("public-layout-wrapper")) return;

  publicRoutePreload ??= Promise.all([
    import("../../app/live/layouts/auth/Layout.vue"),
    import("../../app/live/layouts/docs/Layout.vue"),
    import("../../app/live/auth/login/AuthLoginForm.vue"),
    import("../../app/live/auth/registration/AuthRegistrationForm.vue"),
    import("../../app/live/auth/reset-password/AuthForgotPasswordForm.vue"),
    import("../../app/live/auth/reset-password/AuthResetPasswordForm.vue"),
    import("../../app/live/docs/show/DocsContent.vue"),
  ]).catch(() => undefined);
}
