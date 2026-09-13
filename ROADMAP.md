# Roadmap

Outstanding work, roughly in priority order. Items are grouped by the kind of
risk they carry, not by size.

## Correctness

- [ ] **Honor `unit_system` in the UI.** Users choose metric or imperial at
  registration and in their profile, the value is validated, and then nothing
  reads it. Every weight in every view is hardcoded `kg` — the dashboard's lift
  directives, the training-targets page, the workout logger, the progress cards,
  and the body-metrics form. Decide the boundary (store kg everywhere, convert at
  the view and at form submission), add a helper pair, and sweep the views. An
  imperial user currently gets kilograms labelled as their own units.
## Security

- [ ] **Clear the dependency backlog — CI is red on this today.** `bin/bundler-audit`
  reports **87 advisories across 9 gems**; the lockfile has not been refreshed since
  June. In severity order:

  | Gem | Advisories | Fix |
  | --- | --- | --- |
  | `activestorage` | 1 — arbitrary file read / RCE in variant processing (CVE-2026-66066) | `>= 8.1.3.1` |
  | `nokogiri` | 72 | latest |
  | `crass` | 4 | latest |
  | `loofah` | 3 | latest |
  | `concurrent-ruby` | 3, one High (CVE-2026-54904) | `>= 1.3.7` |
  | `websocket-driver` | 1 High — DoS via malformed Host header (CVE-2026-61666) | `>= 0.8.2` |
  | `rails-html-sanitizer`, `mail`, `json` | 1 each | latest |

  The Active Storage one is the sharp edge: it needs a Rails point release
  (8.1.3 → 8.1.3.1), so it wants its own commit and a full test run rather than
  riding along with anything else.

- [ ] **Re-check `resolv` against CVE-2026-80212 / CVE-2026-80213.** Two
  vulnerabilities were disclosed 2026-08-27 in the `resolv` gem bundled with Ruby.
  `bundler-audit` only covers gems in `Gemfile.lock`, and `resolv` is a default gem
  that does not appear there, so nothing in CI is watching it. Confirm the Ruby
  4.0.6 build in use ships a patched `resolv`, or pin a patched version explicitly.

## Test coverage

- [ ] **No system tests.** `test/integration/` contains only the CSP test. Nothing
  exercises a real browser path — logging a workout, completing a check-in,
  onboarding a new user. `bin/ci` has a commented-out `bin/rails test:system` step
  waiting for this.
- [ ] **No JS tests.** The three Stimulus controllers (`workout_log`,
  `template_editor`, `push`) have zero coverage. `workout_log` in particular
  drives set-row add/remove and is where a regression would silently lose logged
  data.
- [ ] **Thin model coverage.** `test/models/` covers 7 of 27 models. The ones
  carrying invariants worth pinning are `CoachingDecision` (retraction rules and
  the JSONB scopes), `ExercisePrescription` (effective-dating), and `Mesocycle`
  (phase and deload-week math, partially covered).

## Views and navigation

- [x] **Exercise index and detail pages.** `exercises` had only `new`, so there
  was no way to browse the catalog or see a single lift's history.
- [ ] **Per-decision audit view.** The DAG is the product's central claim, but the
  only way to read a decision is through the dashboard's composed summary or the
  AI narrative. A plain "show me this decision, its inputs, its children, and its
  rule version" page would make the audit trail directly inspectable.
- [ ] **Workout session index.** `workout_sessions` has `new`/`show`/`edit` but no
  index. Past sessions are only reachable from the exercise history page.
- [ ] **Turbo's progress bar is silently suppressed.** CSP sets `style-src 'self'`,
  and Turbo injects an inline `<style>` element for `.turbo-progress-bar`, so the
  browser refuses it on every page load — the only visible symptom is a console
  warning and no loading indicator on slow navigations. (Inline `style=`
  *attributes*, like the volume bars', are fine: `style_src_attr :unsafe_inline`
  covers those.) Fix by styling `.turbo-progress-bar` in `application.css` and
  setting `Turbo.setProgressBarDelay`, or by extending the nonce to `style-src`.

- [ ] **Empty-state pass on first run.** A brand-new account with no goal, no
  targets, and no check-in lands on a dashboard that mostly renders placeholders.
  Onboarding covers the first step but not the gap between steps two and five.

## Product

- [ ] **Widen wearable ingestion.** `wearable_samples.metric_type` is
  check-constrained to `hrv_sdnn_ms`, `resting_hr_bpm`, and `sleep_asleep`.
  Workouts, step count, active energy, and body mass are all available from
  HealthKit and all feed things the app already models — `ConditioningSession`,
  `ExpenditureEstimator`, and `BodyMetric` respectively.
- [ ] **Let a mesocycle carry its own targets.** Blocks currently modulate volume
  through `accumulation_set_bonus` and deload weeks, but rep and RIR schemes are
  applied to prescriptions imperatively via `ApplyBlockScheme`. Making the block
  the owner of the scheme would remove the "apply" step and let a block change
  recompose the plan the way every other input does.
- [ ] **Surface retracted decisions.** Retraction is implemented and filtered out
  of every lookup, but nothing shows a user that a recommendation was withdrawn or
  why. That is exactly the transparency the product promises.

## Developer experience

- [ ] **Add a `CLAUDE.md`.** The conventions here are unusually consistent — an
  evaluator owns a `RULE_KEY`/`RULE_VERSION`, snapshots its inputs, short-circuits
  when they are unchanged, and never mutates a prior decision. Writing that down
  keeps new code (and agents) on the rails.
- [ ] **Document the decision types.** There is no single place listing the five
  `decision_type` values, the four link `role` values, and which service owns
  each. It has to be reassembled from check constraints and service constants.
