# Roadmap

12 items, 46 hours in total. Each item lists its hours, what it changes, why. Every item stands alone: it needs no other item and no other item waits for it.

| #   | Item                                       | Hours |
| --- | ------------------------------------------ | ----- |
| 1   | Live sync over a WebSocket                 | 5     |
| 2   | Release builds measured in CI              | 6     |
| 3   | React Native sync tests on the real server | 3     |
| 4   | Undo for deletes                           | 2     |
| 5   | Join by link or QR code                    | 3     |
| 6   | Release signing and store builds           | 4     |
| 7   | Several currencies per group               | 5     |
| 8   | Rotate a group's id                        | 4     |
| 9   | Receipt photos                             | 5     |
| 10  | Accessibility pass                         | 3     |
| 11  | French translation                         | 3     |
| 12  | Web builds of both apps                    | 3     |

## 1. Live sync over a WebSocket (5 hours)

Changes reach other devices on the next sync today. Add `GET /v1/groups/{id}/live`, a WebSocket that sends the new seq whenever a batch is stored.

- Both apps keep 1 socket per open group and run a sync when a seq arrives. The socket only says "something changed", so the sync path stays the 1 path that moves data.
- Re-connect with back-off, and a sync on re-connect in case a message was missed.
- PostgreSQL `LISTEN`/`NOTIFY` fans the seq out when more than 1 server runs.

## 2. Release builds measured in CI (6 hours)

The comparison table in the README has no app size or start-up numbers yet.

- A CI job builds a release APK of each app on the same runner, records the APK size, the download size per ABI, the installed size.
- Start-up time to the 1st frame on an Android emulator, 10 cold starts each, median and spread.
- A script writes the numbers into the README table, so the table and CI never disagree.

## 3. React Native sync tests on the real server (3 hours)

The Jest tests sync against a TypeScript copy of the server's checks. Add a CI job that starts the Dart server with `--memory` and runs the 7 `groupBook` tests against it over HTTP, such that both apps are tested against the same server.

## 4. Undo for deletes (2 hours)

A long press deletes an expense at once. Show a snack bar with Undo for 5 seconds in both apps. Undo writes an expense operation with the deleted version, which the merge already handles.

## 5. Join by link or QR code (3 hours)

Joining needs the group id typed in.

- A `splitken://join/<id>` link plus an https fallback page, handled by both apps.
- A QR code of that link on the group screen, and a scanner on the join screen.

## 6. Release signing and store builds (4 hours)

- Flutter: a release signing config read from `key.properties`, which stays out of git.
- React Native: EAS Build profiles for preview and production.
- iOS signing notes for both, and a CI job that builds unsigned release archives.

## 7. Several currencies per group (5 hours)

- An expense may carry its own currency plus a rate to the group's currency that the user enters, kept as an integer ratio such that both cores convert to the same cent.
- New cases in `spec/cases.json` pin the conversion and its rounding.

## 8. Rotate a group's id (4 hours)

The group id is the only key. Let a member move the group to a new id: the server copies the log, marks the old id as moved, answers it with 410 for everyone without the new id. Both apps follow the move on their next sync.

## 9. Receipt photos (5 hours)

Attach a photo to an expense. The server stores it in object storage with a size limit, the operation holds only its hash, the apps fetch it on demand, then cache it.

## 10. Accessibility pass (3 hours)

Screen reader labels on every control, large text up to 200%, contrast checks for the balance colours, in both apps. Widget tests and Testing Library queries by role keep it from slipping.

## 11. French translation (3 hours)

`intl` with ARB files in Flutter, `i18next` in React Native, the same keys in both. Amounts follow the locale for display, while input keeps 1 format.

## 12. Web builds of both apps (3 hours)

Flutter web builds today, Expo web needs `react-native-web`. Build both in CI and publish them to GitHub Pages, pointed at a demo server.
