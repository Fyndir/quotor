// Captures d'écran du README (docs/screenshots), exécuté dans l'image Playwright.
//
// Prérequis : stack de dev lancée et données de démo chargées
//   docker compose -f docker-compose.dev.yml up -d
//   docker compose -f docker-compose.dev.yml exec app mix run priv/repo/demo.exs
//   docker run --rm --network quotor_default -v "$PWD/scripts:/shots" \
//     -v "$PWD/docs/screenshots:/out" -w /shots mcr.microsoft.com/playwright:v1.49.1-noble \
//     sh -c "npm init -y >/dev/null && npm i playwright@1.49.1 >/dev/null && node screenshots.mjs"
import { chromium } from "playwright";

const BASE = process.env.BASE || "http://app:4000";
const OUT = "/out";
const MONTAGE_QUERY = "Bonjour à tous, je ne suis pas venu ici pour ce film";

const browser = await chromium.launch();

async function shot(page, path, name, { wait = 2500, full = false } = {}) {
  await page.goto(BASE + path, { waitUntil: "networkidle" });
  await page.waitForSelector("[data-phx-main].phx-connected", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(wait);
  // Chromium headless ne décode pas le H.264 : on affiche les affiches (posters)
  await page.evaluate(async () => {
    for (const v of document.querySelectorAll("video")) { v.removeAttribute("autoplay"); v.pause(); v.removeAttribute("src"); v.load(); }
    await Promise.all([...document.querySelectorAll("video[poster]")].map(v => new Promise(r => { const i = new Image(); i.onload = i.onerror = r; i.src = v.poster; })));
  });
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: full });
  console.log("ok", name);
}

// Bureau, thème sombre
const ctx = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  colorScheme: "dark",
  deviceScaleFactor: 1,
  locale: "fr-FR",
});
const page = await ctx.newPage();

await shot(page, "/", "accueil");
await shot(page, "/?q=jeu", "recherche");
// Le montage est rendu en mode avancé, puis capturé sur sa page de partage
await page.goto(BASE + "/?" + new URLSearchParams({ q: MONTAGE_QUERY, mode: "advanced" }));
const montageHref = await page
  .locator("a[href^='/m/']")
  .first()
  .getAttribute("href", { timeout: 30000 });
await shot(page, montageHref, "montage-partage");

const quoteHref = await (async () => {
  await page.goto(BASE + "/?q=catastrophe", { waitUntil: "networkidle" });
  return page.locator("#results article a[href^='/q/']").first().getAttribute("href");
})();
await shot(page, quoteHref, "extrait");
await shot(page, "/mentions-legales", "mentions-legales");

// Connexion admin
await page.goto(BASE + "/users/log-in", { waitUntil: "networkidle" });
await page.fill("#login_form_password input[type=email]", "admin@quotor.local");
await page.fill("#login_form_password input[type=password]", "quotor-admin-dev");
await Promise.all([
  page.waitForURL((u) => !u.pathname.startsWith("/users/log-in")),
  page.click("#login_form_password button[name='user[remember_me]']"),
]);

await shot(page, "/admin", "admin-supervision", { full: true });
await shot(page, "/admin/sources", "admin-sources");
await shot(page, "/admin/signalements", "admin-signalements");
await shot(page, "/admin/logs", "admin-logs");
await ctx.close();

// Mobile, thème clair, utilisateur connecté
const mctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  colorScheme: "light",
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true,
  locale: "fr-FR",
});
const m = await mctx.newPage();
await m.goto(BASE + "/users/log-in", { waitUntil: "networkidle" });
await m.fill("#login_form_password input[type=email]", "demo@quotor.local");
await m.fill("#login_form_password input[type=password]", "quotor-demo-pass");
await Promise.all([
  m.waitForURL((u) => !u.pathname.startsWith("/users/log-in")),
  m.click("#login_form_password button[name='user[remember_me]']"),
]);
await shot(m, "/favoris", "mobile-favoris");
await shot(m, "/?q=soir%C3%A9e", "mobile-recherche");
await mctx.close();

await browser.close();
