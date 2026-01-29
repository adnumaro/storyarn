import { test, expect } from "@playwright/test";

test.describe("Home Page", () => {
  test("should load the home page", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/Storyarn/);
  });

  test("should have working navigation", async ({ page }) => {
    await page.goto("/");
    // Add more specific tests as features are implemented
    await expect(page.locator("body")).toBeVisible();
  });
});
