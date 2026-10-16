---
id: DEV
parent: HOME
order: 4
type: record
title: Deviations
spec_version: 1.3.0
status: approved
updated: 2026-10-15
---

# DEV — Deviations

Every place where the implementation or its history departs from the SpecItOut rev 9 process or from specification 1.3.0. Most come from one cause: the app was built before any lifecycle artifact existed, and the artifacts were written afterwards.

## Process deviations

| # | Expected (rev 9) | What exists | Why | Fix if the process is adopted |
|---|---|---|---|---|
| D-1 | Requirements approved before code (spec-ready gate) | Code first; spec 1.0.0 written afterwards from the code | Built in one session from a prose request | Not recoverable; recorded honestly |
| D-2 | Commits carry `Spec-Ref`, `Work-Item` and `Issue` trailers; untrailed commits refused | None of the 4 commits has trailers | No commit hook, no issues | New commits only. History is not rewritten. |
| D-3 | `trace: R-… <- F-n` in doc comments on implementing declarations | No annotations; this site's Where tables are the only code-to-requirement map | Not in force when built | Add annotations while changing code; `sio trace check` |
| D-4 | `issues` branch with intake, implementation and verification issues | No issues branch | The `sio` issue store was never initialised | Initialise with the bootstrap issue; no retroactive issues (they would be fabricated) |
| D-5 | Work-item branches `work/<item>` and `docs/<work-item>`, merged on review approval | Commits straight to `main`; this site committed straight to `docs` | One-person session | Use the branches from the next change |
| D-6 | Spec test cases written and seen failing before the code (red step) | Tests written alongside the code; no red evidence | Not test-first | Record test evidence from the next change |
| D-7 | Review item RV-n with checklist per work item | Reviews recorded from the owner's in-use acceptance only ([REV](../reviews/index.md)) | No separate reviewer | Run reviews per work item |
| D-8 | Release tags `v1.0.0` … and `trace.json` at Deliver | No git tags; releases are identified by commit | Nothing was released outside the machine | Tag when adopted. Commits are listed in [REL](../releases/index.md). |
| D-9 | Manual and UI cases run as verification items with recorded results | Only the cases in [TEST](../testing.md) with real evidence count as executed | Verification items never existed | Run the remaining manual cases as V items |

## Product deviations from specification 1.3.0

| # | Requirement | Deviation | Impact |
|---|---|---|---|
| P-1 | Bundle versioning (no requirement; release practice) | `CFBundleShortVersionString` is still `1.0.0` in all four releases | Finder shows 1.0.0 for v1.2.0. Cosmetic. |
| P-2 | R-CMUI-005, R-CMUI-006 (Settings) | No automated tests; verified by use only | Regressions in Settings would go unnoticed |
| P-3 | R-CMUI-007 (launch at login) | The `SMAppService` registration has not been exercised. The toggle exists, but there is no record of it being turned on. | Unverified |
| P-4 | R-CMLIM-001 to R-CMLIM-003 | Depend on an undocumented endpoint and Claude Code's private Keychain format (ADR-3) | May break without notice; the panel then shows the error (R-CMLIM-011) |
| P-5 | `PlanUsageClient.storedPlan()` | Public helper that no code calls | Dead code; remove or use |

## Revision history

| Version | Date | Change |
|---|---|---|
| 1.3.0 | 2026-10-15 | v1.2.0 (736d417): no new deviations; P-1 now spans four releases |
| 1.1.0 | 2026-10-15 | v1.0.1 (4a42147): no automated test for the COR-1 fix noted in TEST |
| 1.0.0 | 2026-10-15 | v1.0.0 (29d0828): initial page |
