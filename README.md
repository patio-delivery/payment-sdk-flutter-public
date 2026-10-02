# payment_sdk_flutter

SDK Flutter de **Nexus Payments**. Una app lo agrega como dependencia y, con
un widget, puede cobrar con QR: generar el QR, mostrarlo con un temporizador,
detectar el pago y enterarse del resultado. También puede mostrar los métodos
de pago que la cuenta tiene habilitados.

```text
Tu app Flutter ──► payment_sdk_flutter ──► Nexus Payments ──► Proveedor de pagos
```

El SDK **solo habla con Nexus Payments**. La app dice "quiero cobrar Bs 150" y
Nexus Payments decide con qué proveedor, en qué moneda y a qué cuenta, según la
API key. Nexus Payments es la fuente de verdad del estado de cada pago.

## Contenido

1. [Cómo funciona](#1-cómo-funciona)
2. [Instalación](#2-instalación)
3. [Credenciales y configuración](#3-credenciales-y-configuración)
4. [Modos de integración (V1, V2, V3)](#4-modos-de-integración)
5. [V1 · Direct Payment: `PaymentCheckout`](#5-v1--direct-payment-paymentcheckout)
6. [V2 · Embedded Methods: `PaymentMethods`](#6-v2--embedded-methods-paymentmethods)
7. [V3 · Payment Sheet: `PaymentSheet`](#7-v3--payment-sheet-paymentsheet)
8. [API sin interfaz: `PaymentSdk`](#8-api-sin-interfaz-paymentsdk)
9. [Modelos](#9-modelos)
10. [Errores](#10-errores)
11. [Widgets sueltos](#11-widgets-sueltos)
12. [Tests](#12-tests)
13. [Seguridad](#13-seguridad)
14. [Limitaciones](#14-limitaciones)

---

## 1. Cómo funciona

### 1.1 Capas

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Componentes públicos    PaymentCheckout (V1) · PaymentMethods (V2) ·  │
│                         PaymentSheet (V3)                              │
├──────────────────────────────────────────────────────────────────────┤
│ UI compartida (interna) métodos de pago · tarjeta de cobro · QR ·     │
│                         animaciones                                    │
├──────────────────────────────────────────────────────────────────────┤
│ Sesión de pago (interna) ciclo de vida de UN pago QR:                 │
│   generar · temporizador · consulta de estado · "Ya pagué" · vencer   │
├──────────────────────────────────────────────────────────────────────┤
│ Núcleo público          PaymentSdk · modelos · excepciones             │
├──────────────────────────────────────────────────────────────────────┤
│ Transporte (interno)    HTTP (dio): URL, API key, errores, logs        │
└──────────────────────────────────────────────────────────────────────┘
                                    │ HTTPS
                                    ▼
                              Nexus Payments
```

- **Una sola lógica de pago:** V1, V2 y V3 comparten el mismo ciclo de vida, así
  que el temporizador, la consulta de estado y "Ya pagué" se comportan igual.
- **Lo público es poco:** la app solo importa
  `package:payment_sdk_flutter/payment_sdk_flutter.dart`. Todo lo interno puede
  cambiar sin romper apps.

### 1.2 Vida de un pago QR

```text
 App          Componente SDK                Nexus Payments           Proveedor
  │ monta ──────►│                                │                       │
  │              │── crear pago QR ──────────────►│ genera QR ───────────►│
  │              │◄──── id de pago + imagen ──────│                       │
  │              │   muestra QR + temporizador    │                       │
  │              │── consulta estado (cada 3 s) ─►│                       │
  │              │                                │◄── pago confirmado ───│ el cliente paga
  │              │◄──────────── PAID ─────────────│                       │
  │◄ onSuccess ──│   "¡Pago confirmado!"          │                       │
```

- **El QR** llega como imagen PNG en Base64. El dispositivo no genera ningún QR.
- **El estado se obtiene consultando** a Nexus Payments. La app no necesita
  recibir webhooks.
- **`orderId` es la referencia del pago y debe ser única.** El estado se consulta
  por ella.

### 1.3 Estados que ve el cliente

| Estado | Qué se muestra | Botones |
|---|---|---|
| Inicio (solo V1 sin `autoStart`) | Total a pagar | **Pagar con QR** |
| Generando | "Generando tu código QR…" | — |
| Esperando pago | QR, "Escanea el código…", **temporizador** | **Ya pagué**, Cancelar |
| Verificando | "Verificando tu pago…" | — |
| Pagado | ✓ "¡Pago confirmado!" | — |
| Rechazado | ✗ "Pago rechazado" | Generar nuevo QR, Cancelar |
| Tiempo agotado | "Tiempo agotado" | Generar nuevo QR (sin `onTimeout`) |
| Error al generar | "No pudimos generar el QR" + motivo | Reintentar, Cancelar |

### 1.4 Tiempos y reglas

| Regla | Por defecto | Parámetro |
|---|---|---|
| Vida del QR (temporizador y vencimiento) | 5 min | `qrTimeout` |
| Consulta de estado en segundo plano | cada 3 s | `pollInterval` |
| "Ya pagué": verifica activamente | cada 2 s durante 20 s | `confirmTimeout` |
| Aviso "Aún no recibimos tu pago" | 8 s | — |
| Salida tras "Tiempo agotado" | 4 s, luego `onTimeout` | — |

- **Al llegar a cero** el SDK consulta una última vez: un pago hecho en el
  último segundo cuenta.
- **"Ya pagué" sin pago** vuelve al QR con el tiempo que quedaba.
- **Cancelar** verifica antes de salir: si el QR ya estaba pagado, reporta éxito
  en lugar de cancelar.

### 1.5 Pantallas

Las vistas se adaptan a cualquier pantalla: celulares chicos, celulares en
horizontal, tablets, totems y escritorio.

- **El QR** usa `qrSize` como máximo y se achica para entrar en el ancho
  disponible y en menos de la mitad del alto.
- **La tarjeta, los loaders, los botones y las tarjetas de métodos** cambian de
  tamaño según la pantalla; los métodos se acomodan en 1 o 2 columnas.
- **Los diálogos y la ventana de V3** se desplazan si la pantalla es baja.
- **Los montos largos** se reducen en lugar de desbordar, también con texto
  grande.

---

## 2. Instalación

Requisitos: **Flutter 3.24 o superior** (Dart 3.5).

```yaml
# pubspec.yaml de tu app
dependencies:
  payment_sdk_flutter:
    git:
      url: URL_DEL_REPOSITORIO
      ref: v0.4.0            # fija una versión (tag)
```

```bash
flutter pub get
```

Importa **un solo archivo** en toda tu app:

```dart
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';
```

No importes `package:payment_sdk_flutter/src/...`: es interno.

### Permisos de red por plataforma

| Plataforma | Qué agregar |
|---|---|
| Android | `<uses-permission android:name="android.permission.INTERNET"/>` en `android/app/src/main/AndroidManifest.xml` |
| macOS | `com.apple.security.network.client` = `true` en `DebugProfile.entitlements` y `Release.entitlements` |
| iOS | Nada con `https` |
| Web | Nada |

### Dependencias del SDK

| Paquete | Para qué |
|---|---|
| `dio` | Cliente HTTP: timeouts, logs, errores tipados, transporte reemplazable en tests. |
| `clock` | "Hora actual" testeable (temporizador y consultas). |

No usa librerías de QR, de animación ni de estado, así que no impone
arquitectura a tu app.

---

## 3. Credenciales y configuración

```dart
final payments = PaymentSdk(
  config: PaymentSdkConfig(
    baseUrl: 'https://TU_URL_DE_NEXUS_PAYMENTS/api',
    apiKey: apiKey,
  ),
);

// Cuando ya no se use (p. ej. en dispose):
payments.dispose();
```

La URL y la API key las entrega Nexus Payments al dar de alta la cuenta.

### `PaymentSdkConfig`

| Parámetro | Obligatorio | Por defecto | Qué es |
|---|---|---|---|
| `baseUrl` | sí | — | URL de Nexus Payments **con** `/api`. Debe ser `http(s)` absoluta. |
| `apiKey` | sí | — | API key de la cuenta. Se envía como `Authorization: Bearer <apiKey>`. |
| `timeout` | no | 30 s | Tiempo máximo de cada petición. |
| `defaultQrExpiration` | no | 24 h | Vencimiento si llamas `generateQr` sin `dueDate` (los widgets usan `qrTimeout`). |
| `enableLogging` | no | `false` | Imprime método, URL y código HTTP de cada petición. **Nunca** la key. |

Lanza `ArgumentError` si la URL no es válida o la key está vacía.

### Qué define la API key

Una key = una **cuenta** de Nexus Payments. La cuenta define el proveedor, la
moneda y la notificación al comercio. Por eso el SDK no envía moneda ni
proveedor. Si tu app cobra para varios comercios, crea un `PaymentSdk` por
comercio.

### De dónde sacar la key

**No la escribas en el código**: cualquiera puede extraerla de la app. Lo
recomendado es que **tu backend** la entregue cuando se va a cobrar:

```dart
final creds = await miBackend.obtenerCredencialesDePago(comercioId);
final payments = PaymentSdk(
  config: PaymentSdkConfig(baseUrl: creds.baseUrl, apiKey: creds.apiKey),
);
```

Para pruebas locales usa `--dart-define`, nunca un archivo versionado.

---

## 4. Modos de integración

Un solo SDK, un componente por nivel de integración. Usa el que necesites.

| Modo | Componente | La app dibuja | El SDK dibuja |
|---|---|---|---|
| **V1 · Direct Payment** | `PaymentCheckout` | Carrito, total **y sus métodos de pago** | El cobro QR, cuando la app ya eligió QR |
| **V2 · Embedded Methods** | `PaymentMethods` | Carrito y total | **Los métodos habilitados de la cuenta** y el cobro |
| **V3 · Payment Sheet** | `PaymentSheet.show` | Carrito y botón "Pagar" | **Su propia ventana** con los métodos y el cobro |

### Una sola integración: `PaymentFlow`

Para no integrar cada versión por separado, `PaymentFlow` recibe el pago una
vez y la versión decide qué ve el cliente. La versión se identifica con
`PaymentVersion.v1`, `v2` o `v3`, y se puede leer de configuración:

```dart
// .env, --dart-define, tu backend…: 'v1', 'v2', 'v3' u 'off'
final version = PaymentVersion.tryParse(config); // null = no usar el SDK

PaymentFlow(
  version: version!,
  payments: payments,
  amount: 150,
  orderId: 'ORDER-123',            // o createOrderId
  currency: 'Bs',
  description: 'Pedido 123',
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onCancel: () => volver(),
  onTimeout: () => volver(),
)
```

| Versión | El cliente ve |
|---|---|
| `PaymentVersion.v1` | El QR directo. Con `createOrderId`, primero "Preparando tu pago…" mientras la app crea la orden. |
| `PaymentVersion.v2` | Los métodos de la cuenta y luego el QR. |
| `PaymentVersion.v3` | Un botón "Pagar Bs 150.00" que abre la ventana de pago. Con `autoOpen: true` la abre al aparecer. |

- **Los callbacks significan lo mismo en las tres:** `onSuccess` con el pago
  confirmado, `onCancel` si el cliente sale sin pagar (verificado antes),
  `onTimeout` si el QR vence.
- **Parámetros:** los de V2 más `payLabel` (botón y título de la ventana de
  V3), `methodsTitle`, `autoOpen` y `successDelay`.
- **Cambiar la versión** reinicia el pago con la nueva.
- `PaymentVersion.tryParse` acepta mayúsculas y espacios; cualquier otro valor
  (`'off'`, vacío) devuelve `null`. `label` da `'V1'`, `'V2'`, `'V3'`.

---

## 5. V1 · Direct Payment: `PaymentCheckout`

**Úsalo cuando** tu app ya tiene su pantalla de métodos de pago y solo necesita
que el SDK cobre el QR cuando el cliente lo elige.

```dart
PaymentCheckout(
  payments: payments,
  orderId: 'ORDER-123',            // único por pago
  amount: 150,
  currency: 'Bs',                  // solo se muestra
  description: 'Pedido 123',       // descripción del QR
  autoStart: true,                 // genera el QR al aparecer
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onCancel: () => Navigator.pop(context),
  onTimeout: () => Navigator.pop(context),
  onError: (error) => log(error.message),
)
```

### Parámetros

| Parámetro | Obligatorio | Por defecto | Qué hace |
|---|---|---|---|
| `payments` | sí | — | El `PaymentSdk`. |
| `amount` | sí | — | Monto a cobrar. |
| `orderId` | sí | — | Tu referencia única del pago. |
| `currency` | no | — | Texto junto al monto. **Solo visual**: se cobra en la moneda de la cuenta. |
| `description` | no | `''` | Se muestra bajo el monto y se envía como descripción del QR. |
| `autoStart` | no | `false` | `true`: genera el QR al aparecer. `false`: muestra "Pagar con QR". |
| `qrTimeout` | no | 5 min | Vida del QR y del temporizador. |
| `confirmTimeout` | no | 20 s | Cuánto verifica "Ya pagué". |
| `pollInterval` | no | 3 s | Cada cuánto consulta el estado. |
| `qrSize` | no | 240 | Tamaño del QR en pantalla. |
| `nextOrderId` | no | — | Devuelve un `orderId` nuevo al pedir otro QR. Sin él se reutiliza `orderId`. |

### Callbacks

| Callback | Cuándo se llama |
|---|---|
| `onSuccess(QrPayment)` | Una vez, cuando el pago queda confirmado. |
| `onError(PaymentSdkException)` | En cada error. La vista ya muestra el error. |
| `onStatusChanged(PaymentStatus)` | Cada cambio de estado. |
| `onCancel()` | El cliente toca "Cancelar", después de verificar que no pagó. Sin este callback no aparece el botón. |
| `onTimeout()` | 4 s después de "Tiempo agotado". Sin él se ofrece "Generar nuevo QR". |
| `onNewQr()` | El cliente pide otro QR tras uno rechazado o vencido. Si lo pasas, el SDK no regenera solo. |

---

## 6. V2 · Embedded Methods: `PaymentMethods`

**Úsalo cuando** quieres que la sección de métodos de pago sea del SDK: tu app
muestra carrito y total, y el SDK muestra los métodos habilitados para la
cuenta y cobra el elegido.

```dart
PaymentMethods(
  payments: payments,
  amount: 150,
  orderId: 'ORDER-123',
  description: 'Pedido 123',
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onTimeout: () => Navigator.pop(context),
)
```

**Si tu app crea la orden después de elegir el método**, pasa `createOrderId`
en vez de `orderId`, y opcionalmente `descriptionFor` para que la descripción
incluya el número de orden:

```dart
PaymentMethods(
  payments: payments,
  amount: 150,
  createOrderId: (method) async => await miBackend.crearOrden(),
  descriptionFor: (orderId) => 'Pedido $orderId',
  onSuccess: ...,
)
```

### Qué hace, paso a paso

1. Carga los métodos de la cuenta. Si falla, muestra el motivo y "Reintentar".
2. Muestra solo los métodos que **esta versión del SDK sabe cobrar** (hoy QR).
   Sin métodos: "No hay métodos de pago disponibles".
3. Al tocar QR aparece el diálogo "Prepárate para escanear".
4. Con `createOrderId` muestra "Preparando tu pago…" mientras la app crea la
   orden. Si falla, vuelve a la lista con un mensaje.
5. Muestra el cobro: el mismo QR, temporizador y "Ya pagué" de V1.
6. "Cancelar" (tras verificar que no se pagó) y "Generar nuevo QR" vuelven a la
   lista.

### Parámetros

| Parámetro | Obligatorio | Por defecto | Qué hace |
|---|---|---|---|
| `payments` | sí | — | El `PaymentSdk`. |
| `amount` | sí | — | Monto a cobrar. |
| `orderId` | uno de los dos | — | Tu referencia del pago, si ya existe. |
| `createOrderId` | uno de los dos | — | `Future<String> Function(PaymentMethodInfo)`: crea la orden al elegir el método y devuelve su id. |
| `description` | no | `''` | Descripción del QR y texto bajo el monto. |
| `descriptionFor` | no | — | `String Function(String orderId)`: arma la descripción cuando la orden ya existe. |
| `currency` | no | — | Respaldo visual si la cuenta no informa moneda. |
| `title` | no | `'¿Con qué vas a pagar hoy?'` | Título de la lista. `null` lo oculta. |
| `confirmLabel` / `backLabel` | no | `'Confirmar'` / `'Volver'` | Botones del diálogo de instrucciones. |
| `qrInstructionsTitle` / `qrInstructionsMessage` | no | "Prepárate para escanear" / "Tu código QR aparecerá…" | Texto del diálogo de QR. |
| `qrTimeout` / `confirmTimeout` / `pollInterval` / `qrSize` | no | 5 min / 20 s / 3 s / 240 | Igual que en V1. |

### Callbacks

| Callback | Cuándo se llama |
|---|---|
| `onMethodSelected(PaymentMethodInfo)` | Al confirmar un método, antes de crear la orden. |
| `onSuccess(QrPayment)` | Pago confirmado. |
| `onError(PaymentSdkException)` | Errores del cobro. |
| `onStatusChanged(PaymentStatus)` | Cada cambio de estado del QR. |
| `onCancel()` | El cliente canceló un QR (verificado sin pagar). |
| `onTimeout()` | 4 s después de "Tiempo agotado". |

---

## 7. V3 · Payment Sheet: `PaymentSheet`

**Úsalo cuando** tu app tiene su carrito y un botón "Pagar", y quieres que al
tocarlo el SDK abra **su propia ventana** con los métodos y el cobro, y te
devuelva cómo terminó.

```dart
final result = await PaymentSheet.show(
  context,
  payments: payments,
  amount: 150,
  orderId: 'ORDER-123',            // o createOrderId / descriptionFor, igual que V2
  currency: 'Bs',
  description: 'Pedido 123',
);

switch (result.status) {
  case PaymentSheetStatus.paid:      irAPantallaDeExito(result.payment!);
  case PaymentSheetStatus.expired:   mostrarAviso('El QR venció');
  case PaymentSheetStatus.cancelled: break; // el cliente cerró sin pagar
}
```

### Cómo se comporta

- **Adaptable:** en pantallas angostas sube desde abajo; desde
  `PaymentSheet.dialogMinWidth` (600 px) se abre como ventana centrada.
- **Al pagar** muestra "¡Pago confirmado!" y **se cierra sola** a los 2 s
  (`successDelay`) devolviendo `paid`.
- **Al vencer** el QR, se cierra devolviendo `expired`.
- **Al cerrar** (✕ o botón atrás) con un QR en pantalla, **verifica primero**: si
  ya estaba pagado devuelve `paid`, nunca `cancelled`. Tocar afuera o arrastrar
  no la cierra.

### Parámetros

Los mismos de V2, más:

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `title` | `'Pagar'` | Texto sobre el monto en el encabezado. |
| `methodsTitle` | `'¿Con qué vas a pagar?'` | Título de la lista de métodos. |
| `successDelay` | 2 s | Cuánto se ve "¡Pago confirmado!" antes de cerrar. |

### Resultado: `PaymentSheetResult`

| Campo | Qué es |
|---|---|
| `status` | `paid`, `expired` o `cancelled`. |
| `payment` | El `QrPayment` confirmado (solo con `paid`). |
| `method` | El método que eligió el cliente, si eligió alguno. |
| `isPaid` | Atajo para `status == paid`. |

---

## 8. API sin interfaz: `PaymentSdk`

Para armar tu propia pantalla o hacer cobros sin UI.

| Método | Devuelve |
|---|---|
| `generateQr({orderId, amount, description = '', dueDate?})` | `QrPayment` |
| `getPaymentStatus(orderId)` | `PaymentStatus` |
| `watchPaymentStatus(orderId, {interval = 3 s, timeout = 15 min})` | `Stream<PaymentStatus>` |
| `getPayment(paymentId)` | `QrPayment` |
| `getPaymentMethods()` | `List<PaymentMethodInfo>` |
| `dispose()` | Cierra las conexiones |

```dart
final qr = await payments.generateQr(orderId: 'ORDER-123', amount: 150);
// muestra PaymentQrView(payment: qr)

final sub = payments.watchPaymentStatus('ORDER-123').listen((status) {
  if (status == PaymentStatus.paid) { /* listo */ }
});
// … sub.cancel() al salir
```

- `generateQr` valida antes de enviar (`orderId` no vacío, `amount` > 0,
  `dueDate` futura) y lanza `ValidationException` sin hacer la petición.
- El estado se consulta **por `orderId`**.
- `watchPaymentStatus` emite solo cambios, se cierra en un estado final, sigue
  tras errores reintentables y termina con `StatusWatchTimeoutException` al
  pasar `timeout`.

---

## 9. Modelos

### `QrPayment`
| Campo | Qué es |
|---|---|
| `paymentId` | Id del pago. |
| `qrImageBase64` | Imagen del QR (PNG en Base64). |
| `qrImageBytes` / `hasQrImage` | La imagen decodificada, o `null` si no hay o es inválida. |
| `status` | `PaymentStatus`. |
| `dueDate` | Vencimiento informado por el proveedor. |

### `PaymentStatus`
| Valor | ¿Final? |
|---|---|
| `pending` | no |
| `paid` | sí |
| `failed` | sí |
| `expired` | sí |
| `unknown` (valor nuevo que esta versión no conoce) | no |

### `PaymentMethodInfo`
| Campo | Qué es |
|---|---|
| `code` | Código estable: `QR`, `CARD`… |
| `name`, `description`, `iconUrl` | Para mostrar. |
| `currency` | Moneda de la cuenta que procesa el método. |
| `position` | Orden en que se muestra. |
| `isQr` / `isSupported` | Si es QR / si esta versión del SDK sabe cobrarlo (hoy solo QR). |

---

## 10. Errores

Todo error es un `PaymentSdkException` (clase `sealed`) con `message`,
`statusCode`, `details` e `isRetryable`.

```dart
try {
  await payments.generateQr(orderId: 'ORDER-123', amount: 150);
} on AuthenticationException {
  // API key inválida
} on PaymentSdkException catch (e) {
  mostrar(e.message);
}
```

| Excepción | Cuándo | ¿Reintentable? |
|---|---|---|
| `NetworkException` | Sin conexión, DNS, TLS | sí |
| `RequestTimeoutException` | Se superó `timeout` | sí |
| `AuthenticationException` | 401/403: key ausente, inválida o sin permiso | no |
| `ValidationException` | 400/422 o datos inválidos detectados antes de enviar | no |
| `PaymentNotFoundException` | 404 | no |
| `ProviderException` | 503: falló el proveedor de pagos | sí |
| `RateLimitException` | 429 | sí |
| `BackendException` | Otros 5xx o respuesta inesperada | sí si es 5xx |
| `StatusWatchTimeoutException` | `watchPaymentStatus` superó su `timeout` | no |

---

## 11. Widgets sueltos

| Widget | Parámetros | Muestra |
|---|---|---|
| `PaymentQrView` | `payment`, `size` (240), `unavailableText` | La imagen del QR o "QR no disponible". |
| `PaymentStatusView` | `status`, `labels` | Ícono y texto del estado. |

---

## 12. Tests

```bash
flutter pub get
flutter analyze
flutter test
```

Las pruebas no usan un servidor real: las respuestas HTTP se simulan con
`test/helpers/fake_adapter.dart`.

**Probar tu app sin servidor:** `PaymentSdk` acepta `httpClientAdapter` (un
`HttpClientAdapter` de dio) para simular respuestas.

---

## 13. Seguridad

- La key solo viaja en `Authorization: Bearer`. El SDK no la imprime, no la
  guarda en disco y la oculta en `toString`.
- Entrega la key desde tu backend; no la incluyas en el código de la app.
- **No confíes solo en `onSuccess` para despachar un pedido:** confirma el pago
  también desde tu servidor.
- Usa `https` fuera de desarrollo.

---

## 14. Limitaciones

- **Solo QR por ahora.** V2 y V3 ya están preparadas para más métodos: cuando
  estén disponibles aparecerán sin cambiar las apps.
- **Textos por defecto en español** (configurables en V2 y V3).
