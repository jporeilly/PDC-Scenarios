# Glossary Generator — LLM Setup & Review-Grid Behaviour

*Copper State Credit Union (CSCU) courseware · companion to the Glossary review step*

Two things people ask once the glossary is scanning: how to make the LLM enrichment
faster, and what's safe to click on the review grid without losing work.

---

## 1. Using the local GPU Ollama (the standard CSCU lab setup)

In the CSCU lab the app runs **on the Windows 11 bare-metal host** — the same
machine as the GPUs (dual RTX 3060, 12 GB each) — so the fast setup is simply
the **local** Ollama. No network hop, no firewall rule, and the enriched text
never leaves the machine.

### Configure the app for local GPU Ollama

1. Install/run Ollama on Windows and pull a model sized to your VRAM — with
   12 GB per card a 12–14B model runs fully on GPU (Ollama can also split a
   model across both cards):

   ```
   ollama pull qwen2.5:14b-instruct
   ```

2. Point the app at the **IPv4 loopback** on the **Settings page**
   (CONFIGURE ▸ Settings ▸ LLM): set the Ollama URL to
   `http://127.0.0.1:11434`, pick `qwen2.5:14b-instruct` from the model
   list (or Pull it right there), and Test. (The same values can be
   pinned in `glossary_generator/.env` as `OLLAMA_URL` / `LLM_MODEL` —
   env wins over saved settings on restart.)

   Use `127.0.0.1`, **not** `localhost` — on Windows `localhost` can resolve to
   IPv6 `::1` and miss Ollama's IPv4 bind, which makes the app's LLM status
   dot (sidebar footer) show Ollama as offline even though it's running.

3. Verify: the LLM status (the dot in the sidebar footer; details on the
   Settings page) should read something like
   `Ollama · qwen2.5:14b-instruct · 100% GPU` (the placement comes from
   Ollama's `/api/ps`, the same data as `ollama ps`). A `xx%/yy% CPU/GPU`
   split means the model is too big for VRAM — pick a smaller one or accept
   the slower split.

Do **not** point the app at an Ollama inside the Ubuntu VM — the VM is
CPU-only, and enrichment there is an order of magnitude slower.

### Variant: app running elsewhere, GPUs on this host

If the app ever runs on another machine (e.g. inside the VM), it can still use
this host's GPUs remotely: set a **system** environment variable
`OLLAMA_HOST = 0.0.0.0:11434` on Windows and restart Ollama (it binds only
`127.0.0.1` by default), allow inbound `TCP 11434` through Windows Firewall,
then set the app's Ollama base URL to `http://<windows-host-ip>:11434`.
Trade-offs: the app now depends on this host being up, and the text to be
enriched crosses the network — fine on a lab LAN.

### Multilingual models answer in English (and what to do if they didn't)

Multilingual local models — qwen2.5 included — can drift into their home
language mid-batch, which used to leave rows with Chinese definitions and an
`LLM` chip. Two defences now stand (app 1.8.4+):

- every prompt pins **English output**, and
- a **language guardrail** discards any non-Latin proposal before it touches a
  row — definitions, names, QA rewrites, rationales — so the existing English
  text simply stays.

If a grid already has non-English text from an earlier run, just run the
**AI pass** again — the new run overwrites the drifted text with English (or
reload your last **Save glossary** checkpoint). For a single affected row,
**AI review** on the expanded row is enough.

---

## 2. The agent roster — what each AI button does

Every agent follows the same contract: deterministic rules first, the model
only for judgment, proposals constrained to the governed vocabulary, and the
steward always clicks — no agent applies its own output. Grid-agent results
land as **inline click-to-accept pills** right on the affected cells, batch
by batch while the run streams (there is no proposal popup): accept a pill
to take just that change, or use **Accept all / Dismiss all** from the slim
strip above the grid. The grid never mutates mid-run, and the **LLM**
provenance pill appears only after a proposal is accepted.

| Agent (button) | Proposes | Auto-applies? |
| --- | --- | --- |
| **AI pass (all fields)** | definition, purpose, a clearer name, governed tags, and a category only when the current one is blank — one model call per **batch** of kept rows | Never — **AI →** pills on each affected cell (the expanded editor shows old vs proposed side by side); the name is a **→** chip |
| **AI review** (expanded row) | the same pass, scoped to that one row | Never — the same pills, on that row only |
| **AI advise** (duplicate groups) | Merge / Disambiguate / Keep separate, per group, from evidence + a live value probe + adjudication | Never — hint on the header only |
| **Suggest expertise** (Govern) | roster expertise keywords | Never — marked unsaved until *Save roster* |
| **Draft policies (AI)** (Govern) | PDC pattern/dictionary rule files from detection seeds | Never — a zip you review and import in PDC |

> **One agent, on purpose.** Enrich, AI suggest, AI categorize and the AI QA
> judge were separate buttons until **1.16.0**. They swept the same rows and
> overlapped on name / category / tags, so the last one silently overwrote the
> others — and each restated the guardrails in its own wording, so they drifted.
> The AI pass absorbed all four; QA's deterministic linter survives inside it
> (it runs *before* the model and its flags become rewrite orders), and the
> per-row scope that Enrich/AI suggest were kept for became **AI review**.

Everything works with Ollama offline except the model-judgment parts: the
definition linter still runs (it is deterministic), duplicate advice falls back
to the scan evidence, and the AI pass simply reports offline.

---

## 3. Trying different models — the pass never writes on its own

The **AI pass** proposes rewritten definitions and purposes (and suggests
names/tags/categories) for the kept terms using the selected model. The proposals arrive
as **AI → pills** on the affected cells while the batches stream in —
**nothing touches a row until you accept its pill** (or click **Accept all**
on the strip above the grid). Click a Definition/Purpose preview to see the
old and proposed text side by side before deciding.

That makes model comparison safe by construction:

> Run the pass with model A → inspect the pills → not better? **Dismiss all** →
> switch model in Settings → run with model B → accept the run you prefer.

For a quick comparison you don't need a full sweep: expand one representative
row and use **AI review** on it with each model in turn.

A dismissed run changes nothing. Only one agent run can be pending at a time
(the strip shows "N AI proposals on M rows" until you accept or dismiss).

---

## 4. What's safe vs. destructive on the review grid

| Action | What it does | Loses work? |
| --- | --- | --- |
| **Clear** (by the Filter row) | Resets the filter/search/view only | **No** — terms, edits, accepted AI text all kept |
| **Dismiss all** (proposal strip) | Discards every pending AI proposal pill | **No** — proposals were never applied |
| **Reset all** | Reverts the grid to the **raw scan snapshot** | **Yes** — drops edits, accepted AI text, prune/merge decisions |
| Re-scan / re-harvest the source | Rebuilds the grid from scratch | **Yes** |
| Close / reload the tab without saving | The grid is in-memory | **Yes** — nothing persists until you Save |

**Key point:** the review grid lives in memory. Accepted AI text and edits are **not persisted**
until you click **Save glossary** (or **Generate JSONL** on the Govern page). So before
experimenting with models or big prune/merge operations, **Save glossary** on a state you
like — you can reload it if an experiment goes worse.

- **Clear** = filter reset, always safe.
- **Reset all** = the destructive "back to raw scan" button; use deliberately.
- **Save glossary** = your checkpoint; save early, save before experiments.
