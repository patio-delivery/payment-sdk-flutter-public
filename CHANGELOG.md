# Changelog

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
