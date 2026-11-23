// Drafts: two browsers edit one draft while both are offline. After they
// reconnect, both edits are in the text, on both pages and on the sync server.
//
//   node compiled/test/drafts.mjs <origin of the compiled site>
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, RAILS, sleep, until } from "../bench/env.mjs";

const origin = process.argv[2];
const browser = await chromium.launch();

async function open(context, path) {
  const page = await context.newPage();
  await page.goto(new URL(path, origin).href);
  return page;
}
async function openDraft(context, path) {
  const page = await open(context, path);
  await page.waitForFunction(() => window.Stimulus?.controllers.some(c => c.identifier === "draft"));
  return page;
}
const editor = page => page.locator("textarea.draft-editor");
const text = page => editor(page).inputValue();
const offline = (page, on) => page.locator("[data-inspector-target=offline]").setChecked(on);
async function serverText(path) {
  const html = await (await fetch(RAILS + path)).text();
  return html.match(/">([^<]*)<\/textarea>/)[1];
}

try {
  const a = await browser.newContext();
  const b = await browser.newContext();

  // A creates the draft and writes the first text, online.
  const index = await open(a, "/drafts");
  await index.locator("form.draft-form input[type=text]").fill("Offline test " + randomUUID());
  await index.locator("form.draft-form").evaluate(form => form.requestSubmit());
  await index.waitForURL(/\/drafts\/[^/]+$/);
  const path = new URL(index.url()).pathname;
  // Tabs in one browser share an outbox, so A keeps to this one tab.
  const pageA = index;
  await pageA.waitForFunction(() => window.Stimulus?.controllers.some(c => c.identifier === "draft"));
  await editor(pageA).click();
  await pageA.keyboard.type("Ship it");
  await until("A's first text reaches Rails", async () => (await serverText(path)) === "Ship it");

  const pageB = await openDraft(b, path);
  await until("B loads the text", async () => (await text(pageB)) === "Ship it");

  // Both go offline and edit the same sentence.
  await offline(pageA, true);
  await offline(pageB, true);
  await editor(pageA).click();
  await pageA.keyboard.press("End");
  await pageA.keyboard.type(" today");
  await editor(pageB).click();
  await pageB.keyboard.press("Home");
  await pageB.keyboard.type("Please ");
  assert.equal(await text(pageA), "Ship it today");
  assert.equal(await text(pageB), "Please Ship it");
  await sleep(1000); // past the editor's 300 ms save delay
  assert.equal(await serverText(path), "Ship it", "Offline edits must stay local");

  await offline(pageA, false);
  await until("A's edit reaches Rails", async () => (await serverText(path)) === "Ship it today");
  await offline(pageB, false);
  const merged = "Please Ship it today";
  await until("Rails merges B's edit in", async () => (await serverText(path)) === merged);
  await until("A shows both edits", async () => (await text(pageA)) === merged);
  await until("B shows both edits", async () => (await text(pageB)) === merged);

  const fresh = await openDraft(await browser.newContext(), path);
  await until("a new browser loads the merge", async () => (await text(fresh)) === merged);
  console.log(`Both offline edits survived: "${merged}" on A, B, a new browser and Rails.`);
} finally {
  await browser.close();
}
