# Module 05 — Visualizations (PDC Insights)

**Track:** Technical · **Audience:** Solution Architect / Data Developer

**PDC Insights** is the suite's dashboard app — the third FastAPI + React
app beside the Glossary and Policy Generators, on the same shell. It reads
the suite's read-only governance APIs (vocabulary health, steward audit
summary, drift) and renders **18 built-in dashboards** (three per section);
every dashboard can be downloaded as a spec and printed to PDF
(`print-app.png` shows the print view), and the **AI Builder** at `/chat`
composes new views on request.

No install lab here — the PDC-Demo bootstrap (`install-pdc-demo.ps1`; VM:
`.sh`) already put it at `C:\PDC-Demo\PDC-Insights` and built its UI. Start
it with `.\run.ps1` and open `http://127.0.0.1:5002` (Glossary is on 5000,
Policy on 5001). No live scan yet? Every view has a **Demo data (sample)**
option in its data dropdown, so the dashboards work before the pipeline has
run.

> **Legacy artifacts:** `pdc-insights-1.3.0.zip` and its bundled
> `CHANGELOG.md` in this folder are the old standalone distribution (Flask,
> port 8660). They stay on disk for reference but are no longer the install
> path — use the suite app installed by the bootstrap.

All Copper State Credit Union data is fictional and generated for training.
