# Changelog

## 0.6.0

- **Card payments on a physical POS ("CARD")** in V2 and V3: the customer pays
  on a Bancard POS in the device's network.
  - **Opt-in per device:** `card: CardOptions(terminalId: 'TOTEM100')` in
    `PaymentFlow`, `PaymentMethods` and `PaymentSheet.show`, with
    `onCardPayment` in `PaymentFlow` and `PaymentMethods`. Devices without it
    (a phone, a device without a POS) never see card.
  - **The POS is configured in Nexus Payments**, per device
    (`GET /card/terminals/:code`): its IP, port and connection, `BRIDGE`
    (through the local API POS Bancard service, which now gets the POS's IP
    with every sale) or `DIRECT` (straight to the POS). Editing it there
    applies on the next payment, without releasing the app.
    `CardOptions.manual` and `CardOptions.custom` configure it in the app.
  - Card is hidden when the terminal isn't registered or its POS (or the
    local service) doesn't answer, and is never chosen on its own.
  - Every payment is registered before touching the POS and its result is
    recorded (`POST /card`, `POST /card/:id/result`). An order already paid by
    card is never charged again. While the POS charges there's no going back,
    and V3's window doesn't close.
  - Results: approved (`onCardPayment`, or `PaymentSheetStatus.paid` with
    `result.cardPayment`), rejected (retry or another method), POS unreachable
    (nothing charged, retry), or answer lost (may have been charged: never
    retried from the SDK).
  - Texts: `cardInstructionsTitle`, `cardInstructionsMessage`.
- **`PaymentSdk.chargeCard`** for apps with their own screens, plus
  `getCardTerminal`, `resolveCardTerminal`, `createCardPayment`,
  `reportCardResult` and `getCardPaymentStatus`.
- `CardPayment`, `CardOptions`, `CardTerminal` (with `BancardBridgeTerminal`
  and `BancardDirectTerminal`), `CardTerminalConfig`, `CardConnection`,
  `CardChargeResult`, `BancardResponse` and `CardTerminalException`
  (`outcomeUnknown` says whether the customer may have been charged).
- `PaymentMethodInfo.isCard`; `isSupported` now also covers card.
- **`onBackToMethods`** in `PaymentFlow` (V2) and `PaymentMethods`: the
  methods list shows again after a method was chosen (a QR cancelled, a
  rejected card…), so the app can re-enable what it locked while paying.
- **Upgrading:** nothing changes without `card`. `PaymentSheetResult.payment`
  is null when the sheet ends `paid` by card; read `cardPayment` then.

## 0.5.0

- **Cash payments ("EFECTIVO")** in V2 and V3: the customer gets a code
  (`EF-XXXXXXXX`) to pay at the cashier, and the order stays pending until a
  collector marks it paid or cancels it — the code never expires.
  - **Opt-in per app:** cash is only offered when the app handles it —
    `onCashPayment` in `PaymentFlow` and `PaymentMethods`, `acceptCash: true`
    in `PaymentSheet.show`. Apps that don't pass it never see it, even if the
    account has cash enabled.
  - It is never chosen on its own (not even as the only method): it always
    asks first with "Pagarás en caja". Once the code is on screen there is no
    going back. Retrying returns the same code for the same order.
  - V2 shows the code and calls `onCashPayment`. V3 shows it with "Listo";
    "Listo" or closing the window resolves to the new
    `PaymentSheetStatus.cashPending`, with `result.cashPayment`.
  - Texts: `cashInstructionsTitle`, `cashInstructionsMessage`.
- **`PaymentSdk.createCashPayment`** and **`getCashPaymentStatus`**, and the
  `CashPayment` model.
- **`PaymentStatus.cancelled`** (only cash payments), a final status.
- `PaymentMethodInfo.isCash`; `isSupported` now also covers cash.
- **Upgrading:** exhaustive `switch`es on `PaymentStatus` or
  `PaymentSheetStatus` need the new `cancelled` / `cashPending` cases.

## 0.4.1

- **A single method goes straight to its payment** (V2 and V3): when the
  account has only one method this SDK can charge, the first load skips the
  list and the instructions and shows its QR. Cancelling then shows the
  list, so no new QR is created on its own. With more than one method the
  list is shown as before. `autoSelectSingleMethod: false` turns it off.
- **"Volver" when there is nothing to pay with** (the methods could not be
  loaded or none is available): V3's window always shows it and closes as
  cancelled; V2 shows it when the app passes `onBack` (optional, so apps
  with their own back button do not get two). V1 does not load methods.
- Documentation split: `README.md` explains what the SDK is and how it
  works; `doc/INTEGRACION.md` is the integration guide (requirements,
  installation and the parameters of every version).

## 0.4.0

- **`PaymentFlow`: one integration for every version.** The app passes the
  payment once and `version` (`PaymentVersion.v1`, `v2` or `v3`) decides what
  the customer sees: the QR right away, the methods list, or a pay button
  that opens the payment window (`autoOpen` opens it right away). The
  callbacks (`onSuccess`, `onCancel`, `onTimeout`…) mean the same in all of
  them. In V1, `createOrderId` creates the order before the QR.
- **`PaymentVersion`** with `tryParse` for configuration values (`'v1'`,
  `'V2'`, `' v3 '`; anything else, like `'off'`, is null) and `label`.
- **Responsive views** for small phones, phones in landscape, tablets,
  kiosks and desktop: the QR shrinks to fit the width and under half of the
  screen height; the card, loaders, results, buttons and method cards follow
  the screen size; dialogs scroll when the screen is short; amounts scale
  down instead of overflowing; the payment window is larger on big screens.
- `PaymentCheckout`, `PaymentMethods` and `PaymentSheet` keep their APIs.

## 0.3.0

- **V3 · Payment Sheet:** `PaymentSheet.show(context, …)` opens the SDK's own
  window with the account's payment methods and the checkout, and resolves to
  a `PaymentSheetResult` (`paid`, `expired` or `cancelled`). It slides up from
  the bottom on narrow screens and opens as a centered dialog on wide ones
  (kiosks, tablets, desktop). Closing it while a QR is on screen checks the
  payment first, so a paid QR is never reported as cancelled. After a
  confirmed payment it closes on its own.
- Internal: the "choose a method, then pay" flow moved from `PaymentMethods`
  into a shared `MethodsFlow`, used by V2 and V3. V1 and V2 public APIs are
  unchanged.

## 0.2.0

- **V2 · Embedded payment methods:** `PaymentMethods` widget. The SDK loads
  the account's methods from the backend (`GET /payment-methods`), shows the
  ones it supports (QR for now) and processes the chosen one. Supports orders
  created after the choice through `createOrderId`.
- `PaymentSdk.getPaymentMethods()` and the `PaymentMethodInfo` model. Unknown
  method codes are hidden, so new backend methods never break older apps.
- Internal: the QR payment lifecycle moved out of `PaymentCheckout` into a
  shared `PaymentSession`, with shared `QrPanel`/`SessionView` UI. V1's
  public API and behaviour are unchanged.

## 0.1.0

- **V1 · Direct payment:** `PaymentCheckout` (countdown with
  `qrTimeout`/`onTimeout`, "Ya pagué" confirmation, animated states,
  `onCancel` that checks the payment first, `onNewQr`), `PaymentQrView`,
  `PaymentStatusView`.
- `PaymentSdk` with `generateQr`, `getPayment`, `getPaymentStatus` and
  `watchPaymentStatus`, against the Nexus Payments QR endpoints
  (`POST /qr`, `GET /qr/by-id/:id_payment`, `GET /qr/status/:order`).
- `PaymentSdkConfig` (base URL, API key, timeout, default QR expiration,
  optional logging that never includes headers).
- Typed models: `QrPayment` and `PaymentStatus` (with `unknown` fallback).
- Sealed `PaymentSdkException` hierarchy mapped from HTTP and transport errors.
