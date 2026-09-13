# Roadmap

Outstanding work, roughly in priority order. Items are grouped by the kind of
risk they carry, not by size.

## Correctness

- [x] **`unit_system` is honored across the UI.** Storage stays canonical —
  kilograms and centimetres — so every evaluator, decision and progression
  comparison is unit-agnostic and switching systems changes nothing about a
  user's data. Conversion happens at two boundaries only: `MeasurementsHelper`
  on the way out, `MeasurementParams` on the way in.

  Two things were deliberate. Controllers name their measurement fields
  explicitly instead of the concern inferring them from a `_kg` suffix, because a
  silent name-based rule would quietly capture any future column that matches and
  corrupt stored training data. And decision prose stays in kilograms, since a
  decision is an immutable record; where a decision carries the numbers behind its
  headline, the view composes its own sentence rather than doing string surgery on
  the record, falling back to the stored text when it cannot.

  Conditioning followed: distance and pace were hardcoded to kilometres and
  `/km`. `WeeklyConditioningSummary` now reports exact metres, `ConditioningDirective`
  targets metres and writes no unit into its prose at all, and the view composes
  the progress sentence in the reader's units.

  Remaining: `DoubleProgressionEvaluator` still writes kilograms into two
  `headline` strings. Both are rebuilt by `progression_headline` for display, so
  no user reads them, but making the stored output unit-neutral would need a
  `rule_version` bump.

- [x] **Measurements are stored exactly.** Columns held two decimal places, which
  is coarser than a unit conversion needs: 45.25 lb was stored as 20.53 kg and
  read back as 45.3, and re-saving the set persisted the altered value. Weight
  columns now hold six decimals and length four — the scales are derived, not
  chosen, from what it takes for a typed value to survive the round trip, and the
  tests pin that. `Units` does BigDecimal arithmetic throughout, and nothing is
  padded or truncated to a fixed width: a value renders at the precision it has.
  Measurement inputs take `step="any"`, so a 1.25 kg micro-plate is enterable.

## Security

- [x] **Dependency backlog cleared.** `bundler-audit` reported 24 advisories across
  9 gems (nokogiri is counted once per platform variant, so the raw line count
  looks far larger). All updated, including Rails 8.1.3 → 8.1.3.1 for the Active
  Storage arbitrary-file-read / RCE (CVE-2026-66066).

  `json` is now pinned to `~> 2.19, >= 2.19.9` rather than taking 3.0: json 3.0
  made `JSON.parse` accept its options as keywords, while
  `ActiveSupport::JSON.decode` still passes them positionally, so every jsonb
  attribute raised `ArgumentError` on deserialize — which in this app is every
  coaching decision. 2.19.9 carries the CVE fix, so the pin costs no security.
  Revisit when Rails supports json 3.

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
- [x] **Workout session index.** Past sessions were only reachable from the
  exercise history page; there is now a History page listing them newest first.
- [x] **Turbo's progress bar works again.** CSP set `style-src 'self'`, so the
  inline `<style>` Turbo injects for `.turbo-progress-bar` was refused on every
  page load: no loading indicator, and a console violation. Fixed by noncing
  `style-src` — Turbo signs that element with the `csp-nonce` meta tag — rather
  than adding `'unsafe-inline'`, which would have allowed every inline style on
  the page. The app now loads with zero CSP violations.

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
