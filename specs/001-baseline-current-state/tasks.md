# Tasks: SlideWand — Baseline / Current State

**Input**: Design documents from `specs/001-baseline-current-state/`

**Prerequisites**: spec.md (required), plan.md (required)

**Scope note**: This is a baseline spec for an already-shipped product
(v0.2.4). The implementation tasks for the product itself are complete on
`main`; they are recorded below as done with their evidence paths so the
baseline is traceable. The open tasks are only the baseline's own
verification/documentation work and the one recorded gap (G-001). No new
product scope is created by this file.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story from spec.md (US1–US4)

---

## Phase 1: Onboarding (this baseline)

**Purpose**: Bring the repo under spec-kit + AEE governance without
touching product code.

- [x] T001 Initialize spec-kit in the existing repo (`specify init --here
  --force --non-interactive --integration copilot --script sh`, CLI
  v1.0.10) — evidence: `.specify/` on disk
- [x] T002 Install AEE + evaluator extensions from local clones
  (`specify extension add ~/workspace/electrohire/spec-kit-aee --dev`,
  same for spec-kit-evaluator) — evidence: `.specify/extensions/aee/`,
  `.specify/extensions/evaluator/`, `.specify/extensions.yml`
- [x] T003 Write project constitution grounded in README/RELEASE_NOTES/
  Sources — `.specify/memory/constitution.md` v1.0.0
- [x] T004 [P] Write baseline spec with AEE claims/falsifiers —
  `specs/001-baseline-current-state/spec.md`
- [x] T005 [P] Write as-built plan — `specs/001-baseline-current-state/plan.md`

---

## Phase 2: Shipped Product — Recorded Complete at v0.2.4

**Purpose**: Traceability from spec requirements to shipped code.
All items below are already implemented on `main`; checkboxes reflect
verified presence in the sources, not new work.

- [x] T010 [US1] Hand tracking via Vision 21-landmark pose —
  `Sources/VisionHandTracker.swift` (FR-001)
- [x] T011 [US1] Swipe detection (motion-primary, speed/window gates) —
  `Sources/GestureEngine.swift` SwipeDetector (FR-002)
- [x] T012 [US2] Palm/fist hold detection from finger-extension ratios —
  `Sources/GestureEngine.swift` classifyHand + HoldDetector (FR-003)
- [x] T013 [US1] Ambiguous-pose rejection + cooldown enforcement —
  `Sources/GestureEngine.swift`, `Sources/App.swift` WandController (FR-004)
- [x] T014 [US1] Arrow-key synthesis via CGEvent (124/123) —
  `Sources/KeySender.swift` (FR-005)
- [x] T015 [P] [US1] Camera preview + Gesture Test window (state,
  flashes, counters, event log) — `Sources/App.swift` (FR-006)
- [x] T016 [P] [US4] Preferences with live, persisted tuning —
  `Sources/Tuning.swift`, `Sources/App.swift` PreferencesWindowController (FR-007)
- [x] T017 [US3] Physical-wand calibration (3-step, click-to-pick tip)
  and appearance+rectangle tip tracking with palm fallback —
  `Sources/App.swift` WandController, `Sources/WandCalibration.swift`,
  `Sources/VisionHandTracker.swift` (FR-008)
- [x] T018 [US4] Persistent signing identity enforced for tag builds —
  `.github/workflows/build.yml` (FR-009)
- [x] T019 [P] [US4] Keyless self-updater (6 h throttle, in-place install
  + relaunch) — `Sources/Updater.swift` (FR-010)
- [x] T020 [P] [US4] Accessibility blocked-state banner + re-grant
  walkthrough — `Sources/App.swift`, `Sources/KeySender.swift` (FR-011)

**Checkpoint**: Baseline spec FR-001…FR-011 each map to at least one
shipped source file, verified by inspection during onboarding.

---

## Phase 3: Baseline Verification (open)

**Purpose**: Independently check the baseline's AEE claims (spec.md
C-001…C-006) on a Mac — this Linux VM cannot run the macOS app, so these
are explicitly NOT done by the onboarding pass.

- [ ] T030 [US1] Run the Gesture Test window protocol for C-002/C-003:
  deliberate waves fire once each; held pointing/peace/relaxed poses
  fire zero times. Record the session log as evidence. (Requires a Mac
  with camera + Accessibility grant.)
- [ ] T031 [US4] Verify C-005: install a granted build, update in-app to
  the next release, confirm no blocked banner and keys still land.
- [ ] T032 [P] Verify C-001 by source audit + network observation during
  a non-update session: no outbound traffic other than an updater check.
- [ ] T033 [P] [US1] Verify C-006 in Keynote, PowerPoint, and Google
  Slides: test-window counters and slide advances agree in each.

---

## Gap Register

- **G-001 (from C-004 / Constitution IV partial)**: The 21 gesture-logic
  tests are recorded for the Python prototype (README; goal record), but
  no test target or test files exist in this repo, so the Swift port's
  equivalence is asserted, not re-runnable in-repo.
  - [ ] T040 Port the 21 prototype cases into an in-repo, runnable test
    form for `Sources/GestureEngine.swift` (the engine is framework-free
    precisely to allow this), and record the run in the PR that does it.
    Own future spec; not part of this baseline's scope.

---

## Dependencies & Execution Order

- Phase 1 is complete in the onboarding commit.
- Phase 2 is historical (shipped on `main` through v0.2.4,
  `RELEASE_NOTES.md`); it blocks nothing.
- Phase 3 tasks are independent of each other ([P] where marked) but all
  require a Mac; T030 is the highest-value check (core claims C-002/C-003).
- T040 (G-001) is independent of Phase 3 and should be specced separately
  before implementation, per the constitution's AEE flow.
