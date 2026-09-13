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

- [x] **`resolv` patched and under audit.** Ruby 4.0.6 predates the 2026-08-27
  advisory, so it bundles a vulnerable `resolv`. Declaring `resolv >= 0.7.2` in the
  Gemfile pulls the fix for CVE-2026-80212 and CVE-2026-80213 and puts a default
  gem under `bundler-audit`, which only ever sees what is in the lockfile.

- [x] **Push endpoints are allow-listed.** `push_subscriptions.endpoint` was
  stored unvalidated and the hourly reminder job POSTs to it from the server, so
  any signed-in user could aim it at cloud metadata or an internal service — a
  blind SSRF. Endpoints must now be HTTPS on a vendor push host, extendable via
  `WEB_PUSH_ALLOWED_HOSTS`. Filtering by IP range was rejected deliberately: it
  does not survive a hostname that resolves elsewhere after the check, which is
  CVE-2026-80213 exactly.

## Test coverage

- [x] **System tests exist, starting with the workout logger.** Capybara driving
  Chrome over CDP (Cuprite, so there is no chromedriver version to keep in step
  with Chrome). Seven tests cover the logger: prefilled rows through to saved
  sets, the live volume readout including warm-up exclusion, duplicating a set,
  removing and renumbering, adding an exercise from the catalog search, an
  imperial round trip, and the no-target empty state. Wired into `bin/ci` and
  into CI, which uploads screenshots on failure.

- [x] **System coverage extended past the logger.** `template_editor` and `push`
  are covered, as is the check-in through to the rendered plan — 20 browser tests
  in total. Every Stimulus controller now has tests. The template editor's suite
  found a live bug: a removed row stayed on screen because a class setting
  `display` outranks the user agent's `[hidden]` rule.
- [x] **The invariant-carrying models are covered.** `CoachingDecision`
  (retraction, `active_evidence`, the JSONB scopes, link roles and the
  restrict-on-delete that stops cited evidence disappearing), `DateRanged` and its
  three including models, `ExercisePrescription`, `WorkoutTemplate`, and
  `SetEntry` including the generated 1RM column's precision.

- [ ] **Remaining model files without tests** are mostly thin data holders —
  `ReadinessScore`, `WeightTrend`, `ExpenditureEstimate`, `MuscleGroup` — or are
  exercised through their service tests (`Food`, `BodyMetric`, the wearable
  models). Worth adding only where a rule appears; a test per file for its own
  sake would be noise.

## Views and navigation

- [x] **Exercise index and detail pages.** `exercises` had only `new`, so there
  was no way to browse the catalog or see a single lift's history.
- [x] **Per-decision audit view.** `/coaching_decisions/:id` shows one decision:
  the rule and version that wrote it, what it concluded, the input snapshot it was
  computed from, the decisions it cites and the ones citing it, and its withdrawal
  state. Every node in the dashboard's decision tree and every card in a
  progression trail links into it, and each page links on to its own parents and
  children, so the whole DAG is walkable from today's plan.

  The snapshot renderer assumes nothing about shape — the JSONB is written by
  whichever rule produced the decision — and resolves stored ids back to linked
  names, falling back to the raw id when the record is gone, which is exactly
  what a deleted workout leaves behind.
- [x] **Workout session index.** Past sessions were only reachable from the
  exercise history page; there is now a History page listing them newest first.
- [x] **Turbo's progress bar works again.** CSP set `style-src 'self'`, so the
  inline `<style>` Turbo injects for `.turbo-progress-bar` was refused on every
  page load: no loading indicator, and a console violation. Fixed by noncing
  `style-src` — Turbo signs that element with the `csp-nonce` meta tag — rather
  than adding `'unsafe-inline'`, which would have allowed every inline style on
  the page. The app now loads with zero CSP violations.

- [x] **First-run pass done.** Walking a freshly registered account through every
  page turned up a structural problem rather than a copy one: registration
  redirects to `/onboarding` once and *nothing ever links back to it*, so a user
  who skipped had no way to find out what was missing. The dashboard now carries
  the outstanding steps until setup is done, reading from `OnboardingProgress` —
  one object, so the checklist and the dashboard cannot disagree about what is
  left.

  The dead-end empty states (both on progress, plus conditioning and nutrition)
  now name the action that fills them instead of describing the absence.

## Product

- [x] **Wearable ingestion widened.** Workouts, body mass, steps, active energy
  and basal energy now sync alongside HRV, resting heart rate and sleep. Each one
  becomes a record the app already reads rather than a new kind of thing: a
  workout becomes a `ConditioningSession` (and so feeds the weekly conditioning
  target), a weigh-in becomes a `BodyMetric` (and so feeds the weight trend,
  expenditure and calorie targets), and energy gives `ExpenditureEstimator` a
  second way to answer.

  That second way is deliberately subordinate. Energy balance — intake against
  what the user's weight actually did — is measured outcome and stays primary;
  the device's basal-plus-active figure is a model, so it is only used while
  there is not yet a week of real evidence, never rises above low confidence, and
  is recorded on the row as `basis`. It counts complete local days only: a TDEE
  read off a day at breakfast would have set that day's calorie target at a few
  hundred kilocalories.

  Steps and energy were the one thing that could not be insert-only. They accrue
  all day, so the device sums them per local day and the server treats a repeat
  send as a correction — otherwise a day first synced at lunchtime stayed at its
  lunchtime total forever. Everything else still keys on an immutable HealthKit
  UUID.

  Two bugs fell out of building it. `ExpenditureEstimator` wrote through `save!`
  to a table with no primary key, so the second estimate for any date raised
  `PG::SyntaxError` — it reaches rows through the unique index now, the way
  `WeightTrendMaterializer` always did. And the nutrition page printed the weight
  trend in bare kilograms under a form labelled in pounds.
- [x] **A mesocycle carries its own targets.** Rep and RIR schemes used to be
  *applied*: a button rewrote every active target to the focus's preset,
  superseding each one. Three things were wrong with that. Starting a block did
  nothing until you remembered to press it. Ending a block left its scheme behind
  forever, because nothing knew the numbers had come from anywhere. And a rep
  range you had chosen by hand was gone the first time you pressed it, with no
  way back.

  `TrainingTargets` composes them at read time instead, so starting or ending a
  block recomposes the plan through the same recompute pipeline as every other
  input, and a target's stored numbers stay its own — the fallback for when no
  block is running. `follows_block_scheme: false` opts one lift out and keeps it
  on its own numbers, while still taking the block's volume ramp: opting out says
  "this rep range is mine", not "ignore the block".

  The split that made it work: the block owns the *scheme* (reps, RIR, baseline
  sets), and `DailyTrainingOrchestrator` keeps owning *today's volume* (the
  accumulation ramp, deload and recovery cuts). Both used to be described as
  block behaviour while only one of them was composed.

  `DoubleProgressionEvaluator` goes to `2.0.0`: it judges reps and RIR against
  the composed targets, resolved on the session's own date rather than today, and
  snapshots what was in force and where it came from — the prescription alone no
  longer answers that.
- [x] **Withdrawn decisions are surfaced.** Retraction was implemented, tested and
  filtered out of every lookup, but only the exercise page showed it. Now the
  workout session that caused a withdrawal lists what it no longer recommends,
  and the dashboard says when an earlier version of today's plan was withdrawn
  and why. `CoachingDecision#retraction_explanation` turns the rule's reason into
  a sentence, and one shared partial renders a decision so the three places
  cannot drift apart.

## Developer experience

- [x] **`CLAUDE.md` written.** Covers the evaluator contract, the recompute
  pipeline, the units boundary and its two invariants, and a table of the five
  `decision_type` values and four link roles with the service that owns each —
  which previously had to be reassembled from check constraints.
