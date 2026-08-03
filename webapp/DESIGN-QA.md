# Design QA — screen checklist

A finished sparkline shipped invisible for months. A status dot ignored the field
it was named after. Two controls did nothing. A rendered span was always empty.
None of those survive one pass of somebody opening the running app with this list
beside it — and that pass is the only thing that stops them coming back.

**Run this against the running app, not the source.** Every assertion below is
phrased so it can be confirmed or denied by looking. If an item needs you to read
code to decide, it is written wrong — fix the wording.

**When to run:** before every release, and after any change to a screen listed
here. A failing item is a bug report, not a discussion.

**How to run:**

```bash
cd iris-opcua && docker compose up -d          # iris, plc, plc2, certified-server
cd webapp && npx ng serve                      # http://localhost:4200
```

Some checks need a broken server. `docker compose stop plc` is the switch;
`docker compose start plc` puts it back.

**Driving it from the terminal.** `tools/qa-drive.mjs` seeds a working config,
navigates, and screenshots or evaluates a snippet in the page — useful for the
checks that need a specific server count (§Cross-screen, F24) or for sampling
rendered pixels rather than trusting a computed contrast ratio. Setup command is
in the file's header. It supplements this list; it does not replace looking.

> Sampling matters more than it sounds. Every contrast ratio computed
> analytically for the stopped pipeline card came out optimistic, because each
> calculation missed one compositing step in a stack of four independent
> opacities. The rendered PNG was the only thing that told the truth.

---

## The rule everything below serves

> A value the system does not have must never render in the same treatment as a
> value it does have. Absence is stated in words, in the muted token — never as
> a plausible number, and never as a confident word.

Two screens are the reference for getting this right, and both are worth
re-reading before you judge anything else:

- **Bind Devices**, on a device that browses but matches nothing: *"Can't be
  bound — browsed successfully but matched none of the schema's columns — every
  row would be entirely NULL."* Outcome, then the failure it *isn't*, then the
  mechanism, then the consequence.
- **A pipeline in the `error` state:** *"Enabled, but not collecting data."* The
  status label is "Not collecting", not "Error", because it names the
  consequence.

---

## 1. Node Explorer — not configured

Reachable by clearing `localStorage` and reloading `/explorer`.

- [ ] Exactly one element in the three-step panel looks clickable, and it opens
      Settings. Steps 2 and 3 read as a numbered list — no border, no shadow, no
      pointer cursor.
- [ ] Nothing on the screen has a card border and shadow without responding to a
      click.
- [ ] Body copy is legible: no `opacity-*` on text.

## 2. Node Explorer — tree

- [ ] Every row shows its `ns=` annotation.
- [ ] Folder icons are one colour, the same colour used in the device-binding
      tree. (`Objects` was blue here and amber everywhere else.)
- [ ] The server root row states its security mode **in words** — `Unsecured` or
      `Sign & Encrypt` — not by padlock alone. Desaturate a screenshot: you can
      still tell.
- [ ] The sidebar drags between 200 and 600px.

## 3. Node Explorer — node detail, variable selected (`SA1` on `plc`)

- [ ] The hero value shows a number.
- [ ] `LAST UPDATED` reads as a clock time, `HH:MM:SS`. Not bare milliseconds.
- [ ] `SOURCE TIMESTAMP` shows a time, or the words `not reported`. Never
      `Synchronized`. It may differ slightly from `LAST UPDATED` — that is the
      point of the field.
- [ ] The status dot is green and the label reads `Good`.
- [ ] No empty space reserved beside the hero value for a unit that never comes.
- [ ] There is no telemetry panel. It was removed deliberately; a reinstated
      sparkline needs axes, a time range and a y-scale to be worth the canvas.
- [ ] A long string value is ellipsised (`…`) and shrinks its type size rather
      than overflowing.

## 4. Node Explorer — node detail, folder selected (`Objects`)

- [ ] **The status dot is red.** A folder has no Value attribute, so the read
      returns `BadAttributeIdInvalid` — a Bad status must not render on the
      healthy dot.
- [ ] The status label is words, not a bare integer. The numeric code is
      available on hover.
- [ ] Node class reads `folder`. The data-type field says it is not readable —
      never `String`, which here means only "the read failed".
- [ ] The same value is not printed twice in one card.
- [ ] The breadcrumb does not read `Objects > Objects`.

## 5. Node Explorer — server unreachable

`docker compose stop plc`, then wait three refresh intervals.

- [ ] The card stops asserting the value is current: the value is visibly
      marked stale and the age since the last successful read is on screen.
- [ ] The failure is visible on the card that owns the value, not only on the
      nav-rail dot.
- [ ] Every field either shows real data or says it has none. Nothing shows a
      plausible-looking value.
- [ ] `docker compose start plc` — the card recovers on its own.

## 6. Schemas — library

- [ ] Page title colour matches the Pipelines page title.
- [ ] Stat-card labels are legible (they were `slate-400`, 2.56:1).
- [ ] Delete is disabled for any schema with a non-empty `usedBy`, and says why.
- [ ] Delete confirmation is an in-app dialog, not browser chrome.

## 7. Schemas — builder

- [ ] With no columns and no name, **the reason the Save button is disabled sits
      beside the button**, and updates as each requirement is met. Not 900px
      away in another panel.
- [ ] The template device is shown in a persistent slot, with a way to change or
      clear it.
- [ ] The column remove button is visible without hovering. Complete the whole
      flow with the keyboard only, then again in a touch-emulated viewport.
- [ ] Tree icons and colours match the other trees.
- [ ] The live preview names the class that will be created.

## 8. Bind Devices

- [ ] The mode control has one line of helper text explaining polling vs
      subscription, and it swaps with the mode.
- [ ] The interval label swaps: `Poll interval (seconds)` under polling,
      `Publishing interval (ms)` under subscription.
- [ ] The `Edit as text` summary previews the format without being opened —
      `one device per line, ns=2;s=Name|Label`.
- [ ] Pasting a device list ticks the matching rows in the tree.
- [ ] Listing one device twice produces a warning naming it. It does not block.
- [ ] A device that browses but matches no columns gets the full explanation
      (see the reference above), at row, panel, and button level.
- [ ] The device-row remove button is visible without hovering.
- [ ] Deploy creates the pipeline **stopped**.

## 9. Pipelines — dashboard, one healthy pipeline

- [ ] **No amber anywhere on the page when `ERROR WARNINGS` is 0.** The tile
      shows a check, not a warning triangle, and the numeral is not amber.
- [ ] Decorative background glyphs are smaller and less saturated than the
      numerals they sit behind.
- [ ] Stat-card labels are legible.
- [ ] Every control on the page has an effect. No `ARCHIVED` filter that filters
      nothing; no overflow button with no menu.
- [ ] On the metrics row, values are heavier than their labels — labels are
      static, values change.
- [ ] `LAST ACTIVITY` reads as a relative age (`3s ago`), with the absolute time
      **including timezone** on hover. Never `Invalid Date`.
- [ ] Delete confirmation is an in-app dialog, and still says what survives:
      *"The `AirCon` schema and its collected data are kept."*

## 10. Pipelines — stopped card

- [ ] It still reads as stopped at a glance, without reading a word.
- [ ] `SERVICE`, `NODES`, and the node names all clear 4.5:1. Sample them — this
      card measured 1.54:1.
- [ ] Nothing that is stopped is dimmed with `opacity`; distinction is carried
      by colour and saturation.

## 11. Pipelines — error state

Start a pipeline, `docker compose stop plc`, wait one cycle.

- [ ] The banner appears: *"Enabled, but not collecting data."*
- [ ] Status label reads `Not collecting`. Pulsing red dot, red card border.
- [ ] Exactly one amber element appears on the page — the earned `ERROR
      WARNINGS` tile.
- [ ] Screenshot this. It had never been seen when the audit was written.

## 12. Pipelines — starting state

Enable an item and capture the first cycle.

- [ ] Amber, `hourglass_top`, pulsing dot, label `Starting`.
- [ ] It resolves to `Running` or `Not collecting` — it does not stick.
- [ ] Screenshot this too. Also never seen.

## 13. Pipelines — running but no rows

- [ ] With `health === ok` and `ROWS 0` past a couple of cycles, the card says
      so in words rather than looking identical to a producing pipeline.

## 14. Settings — servers

- [ ] Opening Settings without pressing anything shows **no** green or mint
      block claiming health. An unpressed test has no result.
- [ ] Press Test Connection on a good server and a bad one. Both outcomes appear
      **next to the button**, not only in a corner widget.
- [ ] Each server in the list shows its security mode in words.
- [ ] An unset password field is visibly empty and says `No password set`. A set
      one says `Password set` and offers Change. Empty and filled are never
      pixel-identical.
- [ ] The Security Mode select cannot truncate mid-identifier —
      `Basic256Sha256` and `Basic128Rsa15` are different things.
- [ ] Add a server, type **only** a name, press Save. An error appears at the
      Save button naming the row, and **the row survives**. Silently discarding
      it is data loss.
- [ ] Editing any field clears the error.
- [ ] The UI states that configuration is local to this browser.

## 15. Settings — IRIS API gateway

- [ ] The interval field reads `Auto-refresh interval (seconds)`, with its 1–60
      range stated in helper text.
- [ ] The top bar's indicator is labelled as being about the IRIS API
      specifically — it says nothing about any OPC UA server, and must not imply
      it does.

---

## Cross-screen sweeps

Run these once across the whole app, not per screen.

- [ ] **No `opacity-*` on text.** Icons and decorative glyphs are exempt (SC
      1.4.3 does not cover them); text is not. Every measured contrast failure
      in the audit came from an opacity modifier on a token that passes on its
      own.
- [ ] **Every text/background pair clears 4.5:1**, large text 3:1. Sample, don't
      eyeball.
- [ ] **Every element styled as a control does something.** Card border plus
      shadow plus pointer cursor is a promise.
- [ ] **Every state is reachable by keyboard**, and nothing is revealed only by
      hover. Touch fires neither hover nor focus.
- [ ] **The nav rail does not move** when a server is added.
- [ ] **`npm run build` passes**, which runs the template guard
      (`tools/check-templates.mjs`). It fails on a duplicate attribute — the F2
      root cause — and on new keyboard-unreachable click targets.

---

## When something here fails

File it naming the screen and the item. Do not fix it silently in an unrelated
commit: the value of this list is that the same defect cannot come back
unnoticed, and that depends on the failures being recorded.

If an assertion turns out to be wrong about the product, change the assertion —
but say so out loud. A checklist quietly relaxed to match a regression is worse
than no checklist.
