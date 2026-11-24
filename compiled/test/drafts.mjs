// Drafts: browsers edit a draft's title and text, online and offline, and
// every edit survives the merge. Each scenario starts its own draft.
//
//   node compiled/test/drafts.mjs <origin of the compiled site>
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, RAILS, sleep, until } from "../bench/env.mjs";

const origin = process.argv[2];
const browser = await chromium.launch();
const PLAN = "Ship the beta on Friday.\nTell the support team.\nWrite the release notes.";

const ready = page => page.waitForFunction(() => window.Stimulus?.controllers.some(c => c.identifier === "draft"));
const editor = page => page.locator("textarea.draft-editor");
const titleField = page => page.locator("input.draft-title");
const text = page => editor(page).inputValue();
const title = page => titleField(page).inputValue();
const offline = (page, on) => page.locator("[data-inspector-target=offline]").setChecked(on);
async function serverText(path) {
  const html = await (await fetch(RAILS + path)).text();
  return html.match(/">([^<]*)<\/textarea>/)[1];
}
async function serverTitle(path) {
  const html = await (await fetch(RAILS + path)).text();
  return html.match(/class="draft-title"[^>]*value="([^"]*)"/)[1];
}

// Puts the cursor before `anchor`, or after it, and types `typed` there.
async function typeAt(page, anchor, typed, { after = false, field = editor } = {}) {
  await field(page).click();
  await field(page).evaluate((el, [anchor, after]) => {
    const at = el.value.indexOf(anchor) + (after ? anchor.length : 0);
    el.setSelectionRange(at, at);
  }, [anchor, after]);
  await page.keyboard.type(typed);
}
// Selects `selected` and types over it, or deletes it when `typed` is empty.
async function replace(page, selected, typed) {
  await editor(page).click();
  await editor(page).evaluate((el, selected) => {
    const at = el.value.indexOf(selected);
    el.setSelectionRange(at, at + selected.length);
  }, selected);
  if (typed) await page.keyboard.type(typed);
  else await page.keyboard.press("Backspace");
}

// A creates a draft holding `body` and waits for Rails to have it. The others
// open it.
async function start(title, body, a, ...others) {
  await a.goto(new URL("/drafts", origin).href);
  await a.locator("form.draft-form input[type=text]").fill(`${title} ${randomUUID()}`);
  await a.locator("form.draft-form").evaluate(form => form.requestSubmit());
  await a.waitForURL(/\/drafts\/[^/]+$/);
  await ready(a);
  await editor(a).click();
  await a.keyboard.insertText(body);
  const path = new URL(a.url()).pathname;
  await until(`${title} reaches Rails`, async () => (await serverText(path)) === body);
  for (const page of others) {
    await page.goto(new URL(path, origin).href);
    await ready(page);
    await until(`${title} opens in another browser`, async () => (await text(page)) === body);
  }
  return path;
}

// Waits for Rails and every page to agree on a text that is `expected`, or
// that `expected` accepts when the merge may order the edits either way.
async function settles(label, path, pages, expected) {
  const ok = typeof expected === "function" ? expected : value => value === expected;
  await until(`Rails: ${label}`, async () => ok(await serverText(path)));
  const merged = await serverText(path);
  for (const page of pages) await until(`page: ${label}`, async () => (await text(page)) === merged);
  return merged;
}

try {
  // Tabs in one browser share an outbox, so each browser keeps to one tab.
  const [a, b, c] = await Promise.all([0, 1, 2].map(async () => (await browser.newContext()).newPage()));

  // 1. Online, each browser's typing reaches the other.
  let path = await start("Live", PLAN, a, b);
  await typeAt(a, "Friday", " at noon", { after: true });
  await until("B sees A's edit", async () => (await text(b)).includes("Friday at noon"));
  await typeAt(b, " team", " and sales");
  await settles("both online edits", path, [a, b],
    "Ship the beta on Friday at noon.\nTell the support and sales team.\nWrite the release notes.");
  console.log("1. Online edits reach the other browser.");

  // 2. Offline, edits on different lines both survive.
  path = await start("Lines", PLAN, a, b);
  await offline(a, true);
  await offline(b, true);
  await replace(a, "Friday", "Thursday");
  await typeAt(b, "release notes", " and the blog post", { after: true });
  await sleep(1000); // past the editor's 300 ms save delay
  assert.equal(await serverText(path), PLAN, "offline edits stay in the browser");
  await offline(a, false);
  await offline(b, false);
  await settles("edits on two lines", path, [a, b],
    "Ship the beta on Thursday.\nTell the support team.\nWrite the release notes and the blog post.");
  console.log("2. Offline edits on different lines both survive.");

  // 3. Offline, one browser deletes a line while the other edits the next one.
  path = await start("Delete", PLAN, a, b);
  await offline(a, true);
  await offline(b, true);
  await replace(a, "Tell the support team.\n", "");
  await replace(b, "Write", "Draft");
  await offline(a, false);
  await offline(b, false);
  await settles("a delete and an edit", path, [a, b], "Ship the beta on Friday.\nDraft the release notes.");
  console.log("3. A deleted line stays deleted, and the edit below it survives.");

  // 4. Offline, three browsers add a line at the same place.
  path = await start("Agenda", "Agenda:", a, b, c);
  for (const page of [a, b, c]) await offline(page, true);
  await typeAt(a, "Agenda:", "\n- Budget", { after: true });
  await typeAt(b, "Agenda:", "\n- Hiring", { after: true });
  await typeAt(c, "Agenda:", "\n- Offsite", { after: true });
  for (const page of [a, b, c]) await offline(page, false);
  // Each line arrives whole. Their order depends on the browsers' Yjs client ids.
  await settles("three added lines", path, [a, b, c], value =>
    value.split("\n").slice(1).sort().join("\n") === "- Budget\n- Hiring\n- Offsite" && value.startsWith("Agenda:\n"));
  console.log("4. Three browsers add a line at the same place, and all three lines are kept.");

  // 5. Offline, an edit survives a reload, then merges.
  path = await start("Reload", PLAN, a, b);
  await offline(a, true);
  await offline(b, true);
  await typeAt(b, "Ship", "Please ");
  await sleep(1000);
  await b.reload();
  await ready(b);
  assert.equal(await text(b), "Please " + PLAN, "the reloaded page reads the edit from the browser's database");
  await typeAt(a, "support team", "whole ");
  await offline(a, false);
  await offline(b, false);
  await settles("an edit kept over a reload", path, [a, b],
    "Please Ship the beta on Friday.\nTell the whole support team.\nWrite the release notes.");
  console.log("5. An offline edit survives a reload and merges when the browser reconnects.");

  // 6. Offline, edits to the title and the text all survive.
  path = await start("Fields", PLAN, a, b);
  const named = await title(a);
  await offline(a, true);
  await offline(b, true);
  await typeAt(a, named, " (draft)", { after: true, field: titleField });
  await typeAt(a, "Friday", " at noon", { after: true });
  await typeAt(b, named, "Q3 ", { field: titleField });
  await typeAt(b, "release notes", " and the blog post", { after: true });
  await offline(a, false);
  await offline(b, false);
  await settles("edits to the text", path, [a, b],
    "Ship the beta on Friday at noon.\nTell the support team.\nWrite the release notes and the blog post.");
  const both = `Q3 ${named} (draft)`;
  await until("Rails: edits to the title", async () => (await serverTitle(path)) === both);
  for (const page of [a, b]) await until("page: edits to the title", async () => (await title(page)) === both);
  console.log("6. Offline edits to the title and the text all survive.");
} finally {
  await browser.close();
}
