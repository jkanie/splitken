# splitken

Shared expenses for a group (a trip, a flat, a club) that keep working with
no network. The same app is built twice, in Flutter and in React Native
(Expo), on 1 shared server and 1 shared set of rules, so the 2 stacks can be
compared on equal terms.

- Split an expense 4 ways: equally, by exact amounts, by shares, by percent.
  Cents are whole numbers and left-over cents go out by the largest
  remainder method, so the parts always add up to the amount.
- While you type exact amounts or percentages, the form says how far they
  are from the total: "6.00 is left to assign." or "10% over.".
- See each member's net balance and a short list of payments that settle
  the group. Mark a payment as paid to record it.
- Add, change, delete expenses offline. Changes wait on the device and go
  out on the next sync. 2 devices that edit offline end up with the same
  group, whatever order their changes reach the server in.

## Why 2 apps in 1 repo

A Flutter vs React Native comparison is usually 2 different apps, or 1 toy
counter. Here both apps do the same real job against the same API, and the
parts that must agree are checked to agree:

- `spec/cases.json` holds split, balance, settle-up, merge, parse,
  format cases with their expected results. The Dart core and the
  TypeScript core both run every case in CI, so a rounding rule cannot
  drift between the apps.
- Both apps have the same structure (a `GroupBook` per group, a `Library` of
  groups, the same 3 screens) and the same 7 behaviour tests, so the code
  and tests can be read side by side.

### Measured

Measured on this repo's 1st commit, on a 2-core Linux container, with warm
caches. Line counts leave out blank lines.

| | Flutter 3.50 (Dart 3.14) | React Native 0.88 (Expo SDK 58) |
| --- | --- | --- |
| App code, not counting the shared rules | 927 lines | 1046 lines |
| of which screens | 509 lines | 565 lines, plus a small UI kit (Material ships with Flutter) |
| The shared rules (split, balances, settle-up, merge) | 583 lines, used by the app and the server | 466 lines, a port checked by `spec/cases.json` |
| Tests | 13 app tests, plus 62 core and 18 server tests | 73 tests, 58 of them from `spec/cases.json` |
| What the app tests sync against | The real Dart server in-process | A TypeScript copy of the server's rules |
| Test run | about 6.5 s (`flutter test`) | about 1.8 s (`jest`) |
| Static check | about 9.4 s (`flutter analyze`) | about 1.9 s (`tsc --noEmit`) |
| Packages in the lock file | 72 (`pubspec.lock`) | 1044 (`package-lock.json`) |
| Local storage | `shared_preferences` | `@react-native-async-storage/async-storage` |
| Release JavaScript bundle (Android, Hermes) | n/a | 1.6 MB |

Not measured yet: app size, start-up time, frame times on a device. ROADMAP
item 2 adds them to CI.

What the table does not show:

- Flutter shares 1 language with the server, so the app and the server run
  the same rules code. React Native needs a 2nd copy of the rules, which is
  why the shared cases file exists.
- Flutter's widget tests ran the real server through a mock HTTP client.
  Jest cannot run the Dart server, so the React Native tests use a
  TypeScript copy of its checks (`app_rn/__tests__/fakeServer.ts`).
- React Native's tests start faster, and its type check is quicker.

## Layout

| Path | What it holds |
| --- | --- |
| `spec/cases.json` | Cases both cores must pass |
| `core/` | The rules in Dart: money, splits, balances, settle-up, the operation log with its merge |
| `server/` | The sync server (Dart, shelf, PostgreSQL) |
| `api/openapi.yaml` | The HTTP API |
| `app_flutter/` | The Flutter app (Android, iOS, web) |
| `app_rn/` | The React Native app (Expo, Android, iOS) |

## How sync works

Every change is an operation: add or re-name a member, add or replace an
expense, delete an expense. A device stores its own operations as pending,
folds them with the confirmed ones into the group it shows, then sends them
on sync. The server checks each batch against the group, stores it as 1 step
or refuses all of it (naming the operation that broke a rule), then sends
back every operation the device has not seen.

Between 2 changes to the same expense or member, the change with the higher
`(lamport, clientId, opId)` wins. The merge gives the same result for any
order of the same operations, and an operation sent twice counts once, so a
device may re-try a sync freely. The `fold` cases in `spec/cases.json` check
this in every rotation of each list, forwards and backwards.

A device that asks for operations past the group's newest seq, as after the
server is restored from an older back-up, gets a `seq_ahead` refusal (409).
Both apps then send everything they hold again from seq 0, and the server
keeps each operation once, so the group comes back whole.

Members that devices add get ids that start with the device's client id,
so 2 devices adding members offline never pick the same id.

## Run it

You need Dart 3.9 or later for the server, Flutter 3.50 for the Flutter app,
Node 26 for the React Native app, PostgreSQL 16 for a server that keeps its
data.

### Server

```sh
cd server
dart pub get
dart run bin/server.dart --memory          # nothing kept after exit
DATABASE_URL='postgresql://user:pass@localhost:5432/splitken?sslmode=disable' \
  dart run bin/server.dart                 # PostgreSQL, tables made on start
```

`PORT` sets the port (8080 by default). The server makes its tables on
start.

`GET /v1/groups/{id}/totals` gives what the group spent and each member's
part of it, in cents: `paid` (the expenses they paid) and `share` (their
split shares). A transfer is not spending, so it is left out, and the `paid`
values and the `share` values each add up to `spent`. Both apps read it
with `totals(groupId)` on their API client, which gives `currency` and
`spentCents`, plus 1 entry per member with `paidCents` and `shareCents`.
Changes still pending on a device are not in it until they are synced.

`GET /v1/groups/{id}/expenses.csv` gives the group's expenses as a CSV file
for a spreadsheet: 1 row per expense that is not deleted, members by name,
each participant's share as the split gives it. A description or name that
starts with `=`, `+`, `-`, `@`, their full-width forms, a tab, a carriage
return, a line feed gets a `'` in front, as OWASP's CSV injection page
advises, such that a spreadsheet does not read it as a formula.

### Flutter app

```sh
cd app_flutter
flutter pub get
flutter run --dart-define=SPLITKEN_API=http://10.0.2.2:8080   # Android emulator
flutter run --dart-define=SPLITKEN_API=http://localhost:8080  # iOS simulator, web
```

### React Native app

```sh
cd app_rn
npm ci
EXPO_PUBLIC_SPLITKEN_API=http://10.0.2.2:8080 npx expo start
```

Debug builds may use plain HTTP to a local server. Put the server behind
HTTPS for anything else.

## Tests

```sh
(cd core && dart test)
(cd server && SPLITKEN_TEST_DATABASE_URL='postgresql://...' dart test)   # PostgreSQL tests run when set
(cd app_flutter && flutter analyze && flutter test)
(cd app_rn && npm run typecheck && npm test)
```

CI runs all 4 on every push, with a PostgreSQL 16 service for the server.

## Limits

- A group id works as a key: anyone who has it can read and change the
  group. There are no accounts. Share it only with the group.
- Changes reach other devices on sync, not live.
- Release builds are signed with debug keys until ROADMAP item 6.
- Each member of a group has a name of their own, case aside (Ana and ana are 1 name). The server checks the founders, the apps check a member they add. 2 devices that add the same new name offline still end up with 2 members of that name.
- 1 currency per group. Amounts are at most 10,000,000.00, a group has at
  most 50 members, a sync carries at most 500 operations.
- Deleting an expense has no undo yet.

## Licence

MIT. See [LICENSE](LICENSE).
