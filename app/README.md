# Karots Trade

Offline inventory, customers and money-owed tracker for a small independent seller.
Flutter + SQLite. No account, no server, no internet.

## Run

```sh
flutter run -d linux     # develop on the PC
flutter run -d android   # on a phone
flutter test             # business-rule tests (21)
flutter build apk --release
```

`flutter build apk --release` produces one **universal** APK (arm64-v8a,
armeabi-v7a, x86_64) in `build/app/outputs/flutter-apk/app-release.apk`.

## Signing

Release builds are signed with `android/karots-release.jks`, configured by
`android/key.properties`. Neither is committed. A copy of both, with the
password, lives in `~/karots-signing-key/karots-trade/`. **Keep a copy off
this laptop as well.**
If that keystore is lost, no future build can install over an app already on a
phone — the only way back is uninstall and reinstall, which wipes the database
unless a backup was exported first. Without `key.properties` the build falls
back to the debug key so `flutter run --release` still works on a fresh clone.

## What the app does

Buy → creates price batches. Sell or quote → picks a batch. Quote converts to a sale
once. Items can come back (Return). Payments and advances land on a customer ledger.
A batch entered wrong can be corrected, and the correction is written down.

Every document opens as a receipt preview first; sharing or printing happens from
there, so nothing leaves the app by accident. Files are named the same way every
time: `Sale-0007.pdf`, `Payment-0012.pdf`, `Return-0003.pdf`.

History has a search box (customer name, phone, or document number), a date window,
and Sales / Quotes filters. Payment and return receipts can be reopened any time from
the customer's transaction list.

## Layout

| File | Holds |
|---|---|
| `lib/db.dart` | schema, one SQLite database on every platform |
| `lib/store.dart` | every query and every business rule |
| `lib/models.dart` | plain data classes |
| `lib/core.dart` | money, translations, colours, shared widgets |
| `lib/files.dart` | PDF receipts, backup export/import |
| `lib/screens/` | one file per area of the app |
| `test/business_test.dart` | stock, ledger, quotes, returns, advances, corrections, backup |
| `test/migration_test.dart` | a v1 database on a phone upgrades without losing data |
| `test/ui_test.dart` | screens actually refresh after a save |
| `test/backup_test.dart` | export/restore into a fresh install, row for row |
| `test/receipt_render_test.dart` | every receipt kind, its header and contact line |

UI never touches SQL — screens call `store.dart` only.

## Rules the code enforces

- Money is integer cents. No doubles anywhere near a total.
- Stock cannot go negative: `UPDATE … WHERE qty_left >= ?` inside the transaction.
- Balance is always `SUM(ledger.amount)`. There is no editable balance column.
  Positive = customer owes you, negative = they have an advance.
- Sale prices are copied onto the sale line, so later price changes never rewrite history.
- A quotation moves no stock and writes no ledger entry; conversion is claimed with a
  status guard so it can only happen once.
- Cancelling a sale returns unsold stock and reverses the charge. Money already
  received stays on the ledger as customer credit — it really was received.
- A return puts stock back into the exact batch it left and credits the sale price.
- An advance already on the ledger settles a new sale on the spot: it is recorded on
  the sale as `advance_used` (no second ledger entry, the credit is already there), so
  a sale covered by an advance reads as paid instead of unpaid.
- Correcting a batch changes that batch only. Sales already made keep the price they
  were charged, and every correction is stored with before/after values.
- Backup is one JSON file containing every table plus product photos as base64.

## Decisions worth knowing

- **One database, no adapter layer.** SQLite runs on Android and on the desktop
  (`sqflite_common_ffi`), so the same SQL is what ships. The spec's web/IndexedDB
  adapter existed to work around a browser-only stack that Flutter does not have.
- **Sales and quotations share one table** (`docs`, with a `kind` column). Identical
  fields; splitting them would double the queries for nothing.
- **One `store.dart` instead of nine repository classes.** Same separation of UI from
  SQL, a lot less ceremony. Split it if it ever stops fitting in your head.
- **PDF receipts are English only.** Tamil in a PDF needs a bundled Tamil font; the app
  UI switches language, the receipts do not.
- Purchases record no supplier debt, by design.
- **Package id is `com.karots.karots_trade`.** Changing it makes Android treat
  the result as a different app: separate install, empty database. Leave it.
- **Never write `setState(() => _future = load())`.** The arrow returns the Future,
  `setState` asserts against that, and the rebuild is silently skipped in debug. Use a
  statement body. This shape broke every list and counter in the first version.
