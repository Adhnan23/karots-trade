# Project: Simple Offline Inventory & Customer Management App

## 1. Role

You are an experienced senior React + TypeScript + Capacitor developer.

Build a complete, production-ready MVP Android application for a small independent seller.

The application must be **extremely simple to use**, fast, mobile-first, offline-first, and designed for a non-technical business owner.

The app will first be developed and tested as a normal web application on a PC/browser. It will then be packaged as an Android application using Capacitor.

Do not over-engineer the project. The goal is a simple, reliable business tool, not a full accounting/ERP system.

---

# 2. Business Context

The customer is an independent seller.

He purchases products from suppliers and then sells those products to different shops/customers.

He does NOT need:

- Full accounting
- Cash register/POS functionality
- Expense tracking
- Supplier management
- Employee management
- Online accounts
- Cloud synchronization
- User authentication
- Complex financial reports

The core purpose of the app is:

1. Track products and stock.
2. Track stock using purchase batches.
3. Record purchases.
4. Manage customers.
5. Create sales and quotations.
6. Track customer balances.
7. Record customer payments.
8. Keep transaction history.
9. Generate/share simple PDF receipts.
10. Backup/restore the local database.

Everything should remain as simple as possible.

---

# 3. Technology Requirements

Use:

- React
- TypeScript
- Vite
- Capacitor
- Mobile-first responsive UI
- Local/offline database
- SQLite on Android
- IndexedDB or an equivalent browser-compatible local database for web development/testing

The architecture MUST separate the UI/application logic from the database implementation.

Use a repository/data-access layer so that the application logic does not directly depend on a browser-only or Android-only database API.

Example architecture:

```text
React UI
   ↓
Application / Business Logic
   ↓
Repositories / Services
   ↓
Database Adapter
   ├── Web: IndexedDB
   └── Android: SQLite
```

The same business logic should work on both platforms.

Do not scatter SQL/database calls throughout React components.

---

# 4. Core Design Principle

The application is **offline-first**.

The app must work without internet access.

All important business data is stored locally.

Internet should NOT be required for:

- Adding products
- Buying products
- Selling products
- Creating quotations
- Managing customers
- Recording payments
- Viewing history
- Viewing stock
- Calculating balances

Internet is only potentially needed when the user intentionally shares something through another Android application such as WhatsApp.

---

# 5. Main Navigation

Keep navigation extremely simple.

Recommended primary navigation:

```text
Home
Products
Customers
Buy
Sell / Quote
Settings
```

The exact UI can use bottom navigation, a simple dashboard, or another mobile-friendly approach.

Do not create unnecessary screens.

---

# 6. Home Screen

The home screen should immediately expose the most important actions.

Show large, easy-to-tap buttons/cards for:

- Products
- Customers
- Buy
- Sell / Quote

Also show useful basic information such as:

- Total products
- Total stock items/quantity
- Number of customers
- Outstanding customer balance

Do not turn the home screen into a complicated dashboard.

The customer should be able to understand it immediately.

---

# 7. Product Management

## Product Fields

Each product should have:

- ID
- Name
- Image/photo
- Created date
- Updated date

The product itself represents the generic item.

Example:

```text
Coca-Cola 1L
```

Do NOT store one permanent cost price and selling price directly on the product as the authoritative stock price.

Prices belong to batches.

---

# 8. Batch System

This is one of the most important requirements.

The same product can be purchased multiple times at different prices.

Every purchase with a different cost/selling price must create a separate batch.

Example:

```text
Product:
Coca-Cola 1L

Batch A
Cost: 150
Selling price: 180
Quantity: 20

Batch B
Cost: 160
Selling price: 190
Quantity: 15
```

The product page should show:

```text
Coca-Cola 1L
Total quantity: 35

Batches:

Batch A
Cost: 150
Selling: 180
Available: 20

Batch B
Cost: 160
Selling: 190
Available: 15
```

A batch should contain at least:

- ID
- Product ID
- Cost price
- Selling price
- Original quantity
- Remaining quantity
- Purchase date
- Purchase/reference ID

A batch represents a specific stock acquisition.

---

# 9. Batch Creation Rules

When purchasing an existing product:

If the purchase has a different cost/selling price combination, create a new batch.

Do NOT merge quantities from different price batches.

Example:

Existing:

```text
Coca-Cola
Batch 1
Cost = 150
Selling = 180
Qty = 20
```

New purchase:

```text
Coca-Cola
Cost = 160
Selling = 190
Qty = 10
```

Result:

```text
Batch 1
150 / 180 / 20

Batch 2
160 / 190 / 10
```

If the business logic determines that the exact same batch pricing is being purchased again, it may increase the quantity of that batch rather than unnecessarily creating another batch.

However, preserve purchase history separately.

---

# 10. Products Screen

Display products in a simple mobile-friendly list/grid.

Each product should show:

- Image
- Name
- Total available quantity

Clicking a product opens the product details screen.

Product details should show:

- Image
- Name
- Total stock
- Individual batches
- Cost price per batch
- Selling price per batch
- Available quantity per batch

Allow the user to add/edit the product.

---

# 11. Buy / Purchase Flow

The user needs a very fast way to record purchases.

When the user taps **Buy**:

Open a purchase screen.

The user can add multiple items to one purchase.

Each purchase item should contain:

- Product
- Cost price
- Selling price
- Quantity

The user should be able to:

1. Search/select an existing product.
2. Add a new product directly from the purchase flow if it does not exist.
3. Take/select a product photo when creating a new product.
4. Enter cost price.
5. Enter selling price.
6. Enter quantity.
7. Add additional products.
8. Save the purchase.

When saved:

- Create the appropriate batch(es).
- Increase stock.
- Save purchase history.

---

# 12. Important: No Cash/Supplier Accounting

Do NOT create supplier balances or supplier payment accounting.

The purchase module is only for recording:

```text
What did I buy?
How many?
At what cost?
What selling price should I use?
When did I buy it?
```

Do not build unnecessary supplier/accounting functionality.

---

# 13. Customers

Customer fields:

- ID
- Name
- Phone number
- Created date
- Updated date

That's all that is required.

Do not require addresses, email, tax information, etc.

---

# 14. Customer Screen

Customer details should show:

```text
Customer Name
Phone

Current Balance

[Sell / Quote]
[Payment]

Transaction History
```

The balance must clearly communicate whether:

- Customer owes the seller.
- Seller owes the customer.
- Balance is zero.

Use clear terminology.

Do not confuse positive/negative balances.

---

# 15. Customer Transaction History

Every customer financial transaction should be stored individually.

Examples:

```text
Sale
Payment
Advance Payment
Sale adjustment
```

Each transaction should have:

- ID
- Customer ID
- Type
- Amount
- Date/time
- Reference transaction ID where applicable
- Notes if necessary

Never simply overwrite the customer's balance.

The balance should be calculated from transaction records or maintained safely with a consistent ledger system.

The transaction history is important for auditing.

---

# 16. Sell / Quote Flow

The user should be able to start a sale or quotation from:

- The Sell / Quote button
- A customer page

Flow:

```text
Select customer
        ↓
Select Sale or Quotation
        ↓
Select products
        ↓
Select batch when necessary
        ↓
Enter quantity
        ↓
Calculate total
        ↓
Enter payment
        ↓
Review
        ↓
Save
```

---

# 17. Product Selection During Sale

The product selection screen should be visual and fast.

Show:

- Product image
- Product name
- Available quantity

The seller should be able to quickly select products.

Search should be available.

---

# 18. Multiple Batches During Sale

This is another critical requirement.

If a selected product has multiple available batches, the app must ask the user which batch to use.

Example:

```text
Coca-Cola 1L

Choose batch:

Batch A
Selling price: 180
Available: 20

Batch B
Selling price: 190
Available: 15
```

The seller selects the appropriate batch.

A batch is treated as a distinct stock source during selling.

Do NOT silently mix batches unless explicitly designed and approved.

---

# 19. Sale Item

A sale item should store:

- Product ID
- Batch ID
- Quantity
- Unit selling price
- Total price

The selling price must be captured at the time of the transaction.

If the batch selling price later changes, historical sales must NOT change.

---

# 20. Payment During Sale

The seller can receive:

### Full payment

Example:

```text
Total: 5,000
Paid: 5,000
Balance: 0
```

### Partial payment

Example:

```text
Total: 7,000
Paid: 2,000
Remaining: 5,000
```

### No payment

Example:

```text
Total: 7,000
Paid: 0
Remaining: 7,000
```

The customer's outstanding balance must update correctly.

---

# 21. Customer Advance Payments

A customer may pay money before making a corresponding sale.

Example:

```text
Customer gives 2,000 in advance.
```

The system must support this.

The customer ledger should record an advance/credit balance.

Later transactions can use that balance according to the application's defined accounting rules.

Make the UI very clear about whether money is:

- Customer owes us
- We owe customer / customer has advance
- Settled

---

# 22. Quotation

A quotation is NOT automatically a sale.

When creating a quotation:

- Show customer
- Show selected products
- Show quantities
- Show prices
- Show total
- Show quotation status

Possible statuses:

```text
Draft
Pending
Completed
Cancelled
```

A quotation should NOT reduce stock simply because it was created.

A quotation can later be converted into a sale.

---

# 23. Converting Quotation to Sale

When a quotation is marked as completed/converted to sale:

1. Verify that sufficient stock exists.
2. Deduct the required quantity from the selected batch(es).
3. Create the sale transaction.
4. Update the customer's balance based on payment.
5. Mark the quotation as converted/completed.
6. Preserve the original quotation history.

Do not deduct stock twice.

Do not create duplicate customer debt.

---

# 24. Editing/Deleting Transactions

Be careful with editing/deleting financial and stock transactions.

Do not simply mutate historical data without reversing its effects.

For example, if a completed sale is deleted:

- Restore the sold quantity to the correct batch.
- Reverse the customer ledger effect.
- Remove/reverse associated payment effects.
- Preserve data consistency.

If implementing full editing is too complex for the first version, prefer:

```text
Cancel / Reverse
```

instead of unrestricted editing of completed transactions.

The important requirement is that stock and customer balances never become inconsistent.

---

# 25. Stock Rules

Stock must change predictably.

### Purchase

```text
Purchase quantity
        ↓
Increase batch remaining quantity
```

### Completed sale

```text
Sale quantity
        ↓
Decrease batch remaining quantity
```

### Quotation

```text
Quotation created
        ↓
NO stock reduction
```

### Quotation converted to sale

```text
Convert
   ↓
Decrease stock
```

### Cancelled sale

```text
Reverse sale
   ↓
Restore stock
```

Never allow stock to accidentally become negative.

If insufficient quantity exists, show a clear error.

---

# 26. Customer Balance Rules

Use a proper transaction/ledger model.

Do not rely only on a manually editable `balance` field.

Example:

Customer buys:

```text
Sale = 7,000
Payment = 2,000
```

Result:

```text
Customer owes = 5,000
```

If customer then pays:

```text
Payment = 3,000
```

Result:

```text
Customer owes = 2,000
```

If customer pays in advance:

```text
Advance = 2,000
```

The UI should show that as customer credit/advance rather than incorrectly displaying that the customer owes money.

---

# 27. PDF Receipts

The app should be able to generate simple PDFs for relevant transactions.

Potential documents:

- Purchase receipt
- Sale receipt
- Quotation
- Customer payment receipt

The PDF should include:

- Business name
- Business phone
- Document type
- Date/time
- Customer name where applicable
- Customer phone where applicable
- Items
- Quantity
- Unit price
- Total
- Paid amount
- Remaining balance where applicable
- Appropriate reference/document number

Keep the PDF clean and simple.

---

# 28. Sharing PDFs

On Android, allow the generated PDF to be shared using the native Android share functionality.

The user should be able to choose:

- WhatsApp
- Email
- Files
- Other installed applications

Do not hard-code WhatsApp as the only sharing option.

Use the Android share sheet through Capacitor/native functionality.

---

# 29. Settings

Settings should include:

```text
Business name
Business phone number
```

These values must appear on generated receipts/PDFs.

Also include:

```text
Export database
Import database
```

Potentially include:

```text
Language
```

with:

- English
- Tamil

if time permits.

---

# 30. Tamil Language Support

Tamil support is a bonus but should be designed into the application from the beginning.

Do NOT hard-code user-facing strings directly throughout components.

Use a translation structure.

Example:

```text
English
Tamil
```

The application should be able to switch language.

At minimum, all major navigation labels and common actions should be translatable.

If Tamil localization is not fully completed in the first MVP, keep the architecture ready for it.

---

# 31. Database Requirements

Use a clean relational data model.

Suggested entities:

```text
products
product_batches
purchases
purchase_items
customers
sales
sale_items
quotations
quotation_items
customer_transactions
settings
```

You may add additional tables where necessary.

Use foreign keys where supported.

Every entity should have a stable ID.

Prefer UUIDs or another collision-safe identifier.

Store dates/times consistently.

---

# 32. Suggested Relationships

```text
Product
  └── ProductBatch
          └── PurchaseItem

Customer
  ├── Sale
  │     └── SaleItem
  │            └── ProductBatch
  │
  ├── Quotation
  │     └── QuotationItem
  │            └── ProductBatch
  │
  └── CustomerTransaction
```

A sale item must reference the exact batch from which stock was sold.

---

# 33. Database Abstraction

Create interfaces/services such as:

```text
ProductRepository
BatchRepository
PurchaseRepository
CustomerRepository
SaleRepository
QuotationRepository
CustomerTransactionRepository
SettingsRepository
BackupRepository
```

The React components should not directly execute SQL.

Business operations should be encapsulated in services such as:

```text
purchaseProduct()
createSale()
createQuotation()
convertQuotationToSale()
recordCustomerPayment()
reverseSale()
calculateCustomerBalance()
getAvailableBatches()
```

This is important for maintainability and testing.

---

# 34. Browser Development

The application MUST run in a normal desktop browser during development.

Provide a development mode that works without Capacitor.

For browser persistence use IndexedDB or another suitable local database.

Do not make browser development dependent on native Android plugins.

The UI should still look like a mobile application when viewed in a desktop browser.

A centered mobile-width preview is acceptable during development, but the application should remain responsive.

---

# 35. Android Development

After the web application works correctly:

```text
npm run build
npx cap sync
npx cap open android
```

Use Capacitor for Android packaging and native capabilities.

Android should use SQLite/local persistent storage.

Make sure all native-dependent functionality has a browser-safe fallback where appropriate.

---

# 36. Image Storage

Products have images.

Do not store huge raw image files unnecessarily.

Compress/resize images before storing them where practical.

The application should remain usable with many product images.

Images must persist across app restarts.

When exporting the database, make sure the backup strategy accounts for product images.

Do NOT design a backup system that exports database records while silently losing image references.

---

# 37. Import / Export

The user must be able to back up the app's data.

Export should include all required information:

- Products
- Product batches
- Purchases
- Purchase items
- Customers
- Sales
- Sale items
- Quotations
- Quotation items
- Customer transactions
- Settings
- Product images or a reliable mechanism to preserve them

Import should restore the data correctly.

Before importing, warn the user that existing data may be replaced/merged depending on the chosen implementation.

Prefer a reliable single backup file format.

Do not create a fake "export" that only exports a few database tables.

---

# 38. Data Safety

This is an offline business application, so data integrity is extremely important.

Important operations should behave atomically.

For example, completing a sale should not result in:

```text
stock decreased
but sale not saved
```

or:

```text
sale saved
but customer balance not updated
```

Use database transactions where possible.

---

# 39. UI/UX Requirements

The user is a normal business owner, not a technical person.

The UI should be:

- Simple
- Large touch targets
- Clear
- Fast
- Minimal
- Mobile-first
- Easy to understand
- Low cognitive load

Avoid:

- Complicated dashboards
- Excessive menus
- Technical terminology
- Tiny buttons
- Long forms
- Unnecessary confirmation dialogs
- Excessive animations

Use cards, lists, large action buttons, clear totals, and intuitive navigation.

---

# 40. Currency

Use Sri Lankan Rupees.

Display amounts clearly as:

```text
Rs. 7,500
```

Do not use floating-point arithmetic for financial calculations if avoidable.

Use integer minor units or a safe decimal representation.

For LKR, store monetary values consistently and avoid floating-point rounding bugs.

---

# 41. Search

Add simple search to:

- Products
- Customers
- Product selection during sale

Search should be fast and forgiving.

---

# 42. Validation

Validate:

- Product name required
- Customer name required
- Quantity must be greater than zero
- Prices cannot be negative
- Payment cannot be invalid
- Sale quantity cannot exceed available batch quantity
- Required customer must be selected for customer sales
- Required batch must be selected when necessary

Show human-readable errors.

---

# 43. Empty States

Every list should have a useful empty state.

Examples:

```text
No products yet.

Add your first product.
```

```text
No customers yet.

Add a customer to start selling.
```

Avoid blank screens.

---

# 44. Loading/Error Handling

Handle:

- Database initialization failure
- Image loading failure
- PDF generation failure
- Import failure
- Export failure
- Insufficient stock
- Invalid data

Do not allow silent failures.

Show simple user-friendly messages.

---

# 45. Performance

The app is expected to be used on a normal Android phone.

Keep it lightweight.

Avoid unnecessary libraries.

Avoid unnecessary network requests.

Do not introduce a backend.

Optimize product image loading.

Use pagination or virtualization if lists become large.

---

# 46. Security / Privacy

No cloud account is required.

All business data remains local.

Do not send business/customer information to external servers.

Do not add analytics/tracking unless explicitly requested.

---

# 47. Architecture

Use a clean structure similar to:

```text
src/
  components/
  screens/
  navigation/
  services/
  repositories/
  database/
  models/
  utils/
  i18n/
  hooks/
  assets/
```

Keep business logic outside presentation components.

Avoid giant React components.

Create reusable components for:

- ProductCard
- BatchCard
- CustomerCard
- TransactionRow
- MoneyInput
- ProductSelector
- BatchSelector
- PaymentInput
- EmptyState
- ConfirmDialog

---

# 48. Development Strategy

Build in this order:

## Phase 1 — Foundation

- Vite
- React
- TypeScript
- Capacitor
- Routing
- UI foundation
- Database abstraction
- Web persistence

## Phase 2 — Products

- Product creation
- Image
- Product list
- Product details
- Batches

## Phase 3 — Purchases

- Buy screen
- Add existing product
- Add new product
- Create batches
- Stock updates
- Purchase history

## Phase 4 — Customers

- Customer creation
- Customer list
- Customer details
- Transaction history
- Balance calculation

## Phase 5 — Sales

- Product selection
- Batch selection
- Quantity
- Total
- Payment
- Stock deduction
- Customer ledger

## Phase 6 — Quotations

- Create quotation
- View quotation
- Edit/delete/cancel
- Convert to sale

## Phase 7 — Payments

- Record payment
- Advance payment
- Update customer balance
- Payment history

## Phase 8 — PDFs

- Sale receipt
- Quotation
- Payment receipt
- Purchase record/receipt where appropriate
- Sharing

## Phase 9 — Settings/Backup

- Business information
- Export
- Import
- Language

## Phase 10 — Android

- Capacitor sync
- Native SQLite
- Native sharing
- Android testing
- Build APK

---

# 49. Critical Business Rules

These rules must not be broken:

### Rule 1

Same product can have multiple batches.

### Rule 2

Different purchase pricing should create separate batches.

### Rule 3

Selling must reference a specific batch.

### Rule 4

Historical sale prices must never change when batch prices are edited later.

### Rule 5

Quotation creation does not reduce stock.

### Rule 6

Converting a quotation into a sale reduces stock exactly once.

### Rule 7

Completed sales cannot cause stock to become negative.

### Rule 8

Customer balances must be derived from a consistent transaction ledger.

### Rule 9

Partial payments must correctly reduce outstanding customer debt.

### Rule 10

Advance payments must be represented correctly.

### Rule 11

Deleting/reversing a completed transaction must reverse its stock and financial effects safely.

### Rule 12

Purchase records do not create supplier debt because supplier accounting is outside the project scope.

### Rule 13

Everything must work offline.

### Rule 14

The database backup must preserve all important business data.

---

# 50. Example Scenario

The implementation must support this complete scenario:

## Step 1

Seller creates:

```text
Product:
Coca-Cola 1L
```

with a photo.

## Step 2

Seller buys:

```text
20 units
Cost = Rs. 150
Selling = Rs. 180
```

Create Batch A.

## Step 3

Later seller buys:

```text
15 units
Cost = Rs. 160
Selling = Rs. 190
```

Create Batch B.

Product now has:

```text
Total stock = 35
```

## Step 4

Seller creates customer:

```text
ABC Shop
0712345678
```

## Step 5

Seller creates sale:

```text
ABC Shop
10 Coca-Cola
Batch A
Rs. 180 each
Total = Rs. 1,800
```

Customer pays:

```text
Rs. 1,000
```

Result:

```text
Stock Batch A = 10
Customer owes = Rs. 800
```

## Step 6

Customer later pays:

```text
Rs. 500
```

Result:

```text
Customer owes = Rs. 300
```

The payment appears in transaction history.

## Step 7

Seller creates a quotation for another order.

The quotation does NOT reduce stock.

## Step 8

Customer accepts the quotation.

Seller converts quotation to sale.

The application:

- Checks stock.
- Deducts stock.
- Creates sale.
- Updates customer balance.
- Marks quotation completed.
- Prevents duplicate conversion.

---

# 51. Acceptance Criteria

The application is considered successful when a user can complete this entire workflow without internet:

```text
Create product
↓
Purchase product
↓
Create first batch
↓
Purchase same product at different price
↓
Create second batch
↓
View both batches
↓
Create customer
↓
Create quotation
↓
View quotation
↓
Convert quotation to sale
↓
Select correct batch
↓
Deduct stock
↓
Record partial payment
↓
View customer balance
↓
Record another payment
↓
View transaction history
↓
Generate PDF
↓
Share PDF
↓
Close/reopen app
↓
All data remains available
```

Also test:

```text
Export backup
↓
Clear/reinstall test database
↓
Import backup
↓
Verify products
↓
Verify batches
↓
Verify customers
↓
Verify sales
↓
Verify quotations
↓
Verify payments
↓
Verify images
```

---

# 52. Testing Requirements

Create tests for critical business logic.

At minimum test:

- Batch creation
- Stock increase
- Stock decrease
- Insufficient stock
- Multiple batches
- Sale using correct batch
- Quotation does not affect stock
- Quotation conversion
- Prevent duplicate conversion
- Full payment
- Partial payment
- Zero payment
- Advance payment
- Customer balance
- Reversing a sale
- Database import/export

Do not rely only on manually testing the UI.

---

# 53. Important Implementation Philosophy

Do not build features that were not requested.

Do not turn this into:

- Accounting software
- POS software
- ERP
- CRM
- E-commerce platform
- Cloud inventory platform

Keep the application focused.

The customer wants a simple tool for:

```text
BUY
STOCK
SELL
CUSTOMERS
MONEY OWED
PAYMENTS
QUOTATIONS
RECEIPTS
BACKUP
```

---

# 54. AI Agent Working Rules

Before writing a large amount of code:

1. Inspect the existing project.
2. Create a clear implementation plan.
3. Identify architectural decisions.
4. Implement incrementally.
5. Keep the application runnable after each major phase.
6. Do not replace working code unnecessarily.
7. Do not add unnecessary dependencies.
8. Do not invent business requirements.
9. Follow the business rules in this document exactly.
10. If a requirement is ambiguous, choose the simplest behavior consistent with the requirements and document the decision.

When implementing a feature, also update:

- Types/models
- Repository
- Business logic
- UI
- Validation
- Error handling
- Tests where appropriate

Do not implement only the UI while leaving fake/mock data underneath.

---

# 55. Definition of Done

The final application must:

- Run in the browser.
- Work offline.
- Persist data.
- Manage products.
- Manage product images.
- Manage batches.
- Record purchases.
- Track stock.
- Manage customers.
- Create sales.
- Create quotations.
- Convert quotations to sales.
- Track partial/full/unpaid sales.
- Support customer payments.
- Support customer advances.
- Show customer transaction history.
- Generate PDFs.
- Share PDFs on Android.
- Store business information.
- Export/import backup data.
- Be ready for Tamil localization.
- Be packaged using Capacitor for Android.
- Have no major stock/balance calculation bugs.

---

# 56. Final Priority

When time is limited, prioritize in this exact order:

```text
1. Data correctness
2. Stock correctness
3. Customer balance correctness
4. Purchase/batch functionality
5. Sale functionality
6. Quotation functionality
7. Payment functionality
8. Simple usable UI
9. Backup/import/export
10. PDF receipts
11. Android integration
12. Tamil localization
13. Cosmetic polish
```

A simple app with correct data is much more valuable than a beautiful app with broken stock or customer balances.

Build the smallest reliable version first, then improve the UI and bonus features.