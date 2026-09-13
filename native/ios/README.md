# PerformanceOS HealthKit arm

This directory contains the native HealthKit ingestion layer intended to sit inside a Hotwire Native iOS shell.

## Required capabilities

- HealthKit
- Background delivery
- Background processing

Add these read permissions to `Info.plist`:

- `NSHealthShareUsageDescription`: PerformanceOS reads sleep, HRV, resting heart rate, workouts, body weight, steps and energy to generate daily training and nutrition recommendations.
- `NSHealthUpdateUsageDescription`: PerformanceOS does not currently write HealthKit data.

## Pairing flow

1. The authenticated Hotwire web view posts to `POST /wearable_devices` with:
   - `platform=ios_healthkit`
   - a stable Keychain-backed installation UUID as `external_id`
   - a user-facing device name
2. The endpoint returns a one-time `access_token` and `sync_url`.
3. Store the token in Keychain. The server stores only a BCrypt digest.
4. Pass the token and sync URL to `HealthKitSyncCoordinator`.

Re-pairing the same installation rotates the token. Revoking the device immediately invalidates background sync.

## What is synced

| Metric type | HealthKit source | Unit | Becomes |
| --- | --- | --- | --- |
| `hrv_sdnn_ms` | `heartRateVariabilitySDNN` | `ms` | the day's readiness check-in |
| `resting_hr_bpm` | `restingHeartRate` | `bpm` | the day's readiness check-in |
| `sleep_asleep` | `sleepAnalysis` (asleep values) | `minutes` | the day's readiness check-in |
| `workout` | `HKWorkout` | `seconds` | a conditioning session |
| `body_mass_kg` | `bodyMass` | `kg` | a weigh-in, and through it the weight trend |
| `step_count` | `stepCount` | `count` | the day's activity readout |
| `active_energy_kcal` | `activeEnergyBurned` | `kcal` | an expenditure estimate |
| `basal_energy_kcal` | `basalEnergyBurned` | `kcal` | an expenditure estimate |

A workout carries the shape of the session in `metadata` rather than in fields of
its own — `activity_type` (already mapped into the server's eight-way vocabulary
by `HKWorkoutActivityType.performanceOSActivityType`), `distance_meters` and
`avg_hr_bpm`, each optional. Its `value` is the workout's own elapsed duration,
not the wall-clock span, so a paused run does not count the time spent stopped.

## Sync behavior

- HealthKit sample UUIDs become immutable server-side idempotency keys.
- Values cross the API in canonical units: the server converts nothing and
  rejects a sample whose `unit` disagrees with its `metric_type`.
- The server accepts at most 1,000 samples per batch.
- Replaying a batch is safe; duplicates are reported but not reinserted.
- Steps and energy are the exception to all of that. They accrue all day and
  would otherwise be hundreds of fragments per day per metric, so the device
  sums them into one row per local day with `"<metric_type>:<yyyy-mm-dd>"` as the
  external ID. The server treats a repeat send of one of those as a correction
  rather than a duplicate, which is what lets a day synced at noon finish
  counting. Every other metric stays insert-only.
- Sleep is assigned to the local day in which the segment ends. Everything else
  is assigned to the day it starts.
- HRV and resting-heart-rate recommendations remain low confidence until seven
  prior daily observations establish a personal baseline.
- Expenditure estimated from device energy is always low confidence and is only
  used while there is not yet a week of intake and weight-trend evidence to
  estimate it from measured outcome instead. It counts complete days only, so
  syncing at breakfast cannot collapse the day's calorie target.

The production shell should run a sync:

- after HealthKit authorization,
- when the app enters the foreground,
- from an `HKObserverQuery` background-delivery callback,
- before loading the daily dashboard when practical.
