# PerformanceOS HealthKit arm

This directory contains the native HealthKit ingestion layer intended to sit inside a Hotwire Native iOS shell.

## Required capabilities

- HealthKit
- Background delivery
- Background processing

Add these read permissions to `Info.plist`:

- `NSHealthShareUsageDescription`: PerformanceOS reads sleep, HRV, and resting heart rate to generate daily readiness recommendations.
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

## Sync behavior

- HealthKit sample UUIDs become immutable server-side idempotency keys.
- Values cross the API in canonical units: milliseconds, beats per minute, and minutes asleep.
- The server accepts at most 1,000 samples per batch.
- Replaying a batch is safe; duplicates are reported but not reinserted.
- Sleep is assigned to the local day in which the segment ends.
- HRV and resting-heart-rate recommendations remain low confidence until seven prior daily observations establish a personal baseline.

The production shell should run a sync:

- after HealthKit authorization,
- when the app enters the foreground,
- from an `HKObserverQuery` background-delivery callback,
- before loading the daily dashboard when practical.
