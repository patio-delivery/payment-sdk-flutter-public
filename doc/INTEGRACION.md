# Guía de integración · payment_sdk_flutter

Cómo agregar el SDK de pagos de Nexus Payments a una app Flutter: requisitos,
instalación y los parámetros de cada versión. Para saber qué es el SDK y cómo
funciona por dentro, lee el [README](../README.md).

## Contenido

1. [Requisitos](#1-requisitos)
2. [Instalación](#2-instalación)
3. [Credenciales](#3-credenciales)
4. [Elegir la versión](#4-elegir-la-versión)
5. [`PaymentFlow`: una integración para todas las versiones](#5-paymentflow-una-integración-para-todas-las-versiones)
6. [V1 · `PaymentCheckout`](#6-v1--paymentcheckout)
7. [V2 · `PaymentMethods`](#7-v2--paymentmethods)
8. [V3 · `PaymentSheet`](#8-v3--paymentsheet)
9. [Qué significa cada callback](#9-qué-significa-cada-callback)
10. [Pago en efectivo](#10-pago-en-efectivo)
11. [Pago con tarjeta (POS)](#11-pago-con-tarjeta-pos)
12. [Ejemplos completos](#12-ejemplos-completos)
13. [Sin interfaz: `PaymentSdk`, modelos y widgets sueltos](#13-sin-interfaz-paymentsdk-modelos-y-widgets-sueltos)
14. [Errores](#14-errores)
15. [Lista de verificación](#15-lista-de-verificación)
16. [Problemas comunes](#16-problemas-comunes)

---

## 1. Requisitos

| Requisito | Detalle |
|---|---|
| Flutter | **3.24 o superior** (Dart 3.5). |
| Cuenta de Nexus Payments | La **URL** del backend (con `/api`) y la **API key** de la cuenta del comercio. |
| Backend propio (recomendado) | Un servicio tuyo que entregue la API key a la app cuando va a cobrar, para no guardarla en el código. |
| Referencia de pago | Un `orderId` **único por pago** (o una función que lo cree). |
| Red | Permiso de internet en Android y macOS (ver abajo). |
| V2 y V3 | El backend debe tener `GET /api/payment-methods`. Sin él, la lista de métodos muestra un error. |
| Efectivo (opcional) | La cuenta con efectivo habilitado y el backend con `POST /api/cash`. Ver [sección 10](#10-pago-en-efectivo). |
| Tarjeta (opcional) | Un POS Bancard en la misma red del equipo, la cuenta con tarjeta habilitada y el equipo registrado como terminal en Nexus Payments. Ver [sección 11](#11-pago-con-tarjeta-pos). |

### Permisos de red

| Plataforma | Qué agregar |
|---|---|
| Android | `<uses-permission android:name="android.permission.INTERNET"/>` en `android/app/src/main/AndroidManifest.xml` |
| macOS | `com.apple.security.network.client` = `true` en `DebugProfile.entitlements` y `Release.entitlements` |
| iOS | Nada con `https` |
| Web | Nada |

Solo para probar contra un backend local por `http`: Android necesita
`android:usesCleartextTraffic="true"` en el manifest de debug (desde el
emulador, `localhost` es `10.0.2.2`).

---

## 2. Instalación

En el `pubspec.yaml` de tu app:

```yaml
dependencies:
  payment_sdk_flutter:
    git:
      url: https://github.com/patio-delivery/payment-sdk-flutter-public.git
      ref: v0.6.0            # usa siempre un tag: fija la versión
```

```bash
flutter pub get
```

Importa **un solo archivo** en toda la app:

```dart
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';
```

No importes `package:payment_sdk_flutter/src/...`: es interno y puede cambiar.

**Para actualizar:** cambia el `ref` al tag nuevo y corre `flutter pub get`.
Commitea `pubspec.yaml` y `pubspec.lock` juntos.

---

## 3. Credenciales

Crea un `PaymentSdk` con la URL y la API key de la cuenta del comercio:

```dart
final payments = PaymentSdk(
  config: PaymentSdkConfig(
    baseUrl: 'https://TU_URL_DE_NEXUS_PAYMENTS/api',
    apiKey: apiKey,
  ),
);

// Cuando ya no se use (por ejemplo en dispose):
payments.dispose();
```

| Parámetro | Obligatorio | Por defecto | Qué es |
|---|---|---|---|
| `baseUrl` | sí | — | URL de Nexus Payments **con** `/api`. `http(s)` absoluta. |
| `apiKey` | sí | — | API key de la cuenta. Viaja como `Authorization: Bearer <apiKey>`. |
| `timeout` | no | 30 s | Tiempo máximo de cada petición. |
| `defaultQrExpiration` | no | 24 h | Vencimiento del QR si usas `generateQr` sin `dueDate`. Los componentes usan `qrTimeout`. |
| `enableLogging` | no | `false` | Imprime método, URL y código HTTP de cada petición. Nunca la key. |

- **Una API key = una cuenta.** La cuenta define el proveedor, la moneda y a
  quién se notifica el pago. Si tu app cobra para varios comercios, crea un
  `PaymentSdk` por comercio.
- **No escribas la key en el código.** Lo recomendado es que tu backend la
  entregue cuando se va a cobrar:

```dart
final creds = await miBackend.obtenerCredencialesDePago(comercioId);
final payments = PaymentSdk(
  config: PaymentSdkConfig(baseUrl: creds.baseUrl, apiKey: creds.apiKey),
);
```

---

## 4. Elegir la versión

| Versión | Úsala cuando… | La app dibuja | El SDK dibuja |
|---|---|---|---|
| **V1** | Tu app ya tiene su pantalla de métodos de pago y solo necesita cobrar el QR. | Carrito, total y sus métodos | El cobro QR |
| **V2** | Quieres que los métodos de pago los decida el backend y se muestren en tu pantalla. | Carrito y total | Los métodos habilitados y el cobro |
| **V3** | Quieres un botón "Pagar" que abra una ventana de pago completa. | Carrito y botón | Su propia ventana con métodos y cobro |

Dos formas de integrar:

- **`PaymentFlow` (recomendada):** integras una vez y eliges la versión con
  `PaymentVersion.v1`, `v2` o `v3`, incluso desde configuración. Cambiar de
  versión no requiere tocar código.
- **El componente de una sola versión:** `PaymentCheckout` (V1),
  `PaymentMethods` (V2) o `PaymentSheet.show` (V3). Útil si solo necesitas
  una versión o algún parámetro que solo ese componente tiene.

---

## 5. `PaymentFlow`: una integración para todas las versiones

```dart
PaymentFlow(
  version: PaymentVersion.v2,
  payments: payments,
  amount: 150,
  orderId: 'ORDER-123',
  currency: 'Bs',
  description: 'Pedido 123',
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onCancel: () => volver(),
  onTimeout: () => volver(),
)
```

### Leer la versión desde configuración

`PaymentVersion.tryParse` acepta `'v1'`, `'V2'`, `' v3 '`… Cualquier otro
valor (`'off'`, vacío, `null`) devuelve `null`: úsalo para decidir si se usa el
SDK.

```dart
// .env, --dart-define, tu backend…
final version = PaymentVersion.tryParse(configuracion['PAYMENT_SDK_MODE']);

if (version == null) {
  // SDK apagado: usa tu flujo de pago propio.
} else {
  // PaymentFlow(version: version, ...)
}
```

`version.label` devuelve `'V1'`, `'V2'` o `'V3'` (para mostrar o registrar).

### Parámetros

**Obligatorios**

| Parámetro | Tipo | Qué es |
|---|---|---|
| `version` | `PaymentVersion` | `v1`, `v2` o `v3`. Cambiarla reinicia el pago con la nueva versión. |
| `payments` | `PaymentSdk` | El SDK con las credenciales del comercio. |
| `amount` | `num` | Monto a cobrar. |
| `orderId` **o** `createOrderId` | ver abajo | Uno de los dos es obligatorio. |

**La orden**

| Parámetro | Tipo | Qué es |
|---|---|---|
| `orderId` | `String?` | Tu referencia única del pago, si la orden ya existe. |
| `createOrderId` | `Future<String> Function(PaymentMethodInfo)?` | Crea la orden y devuelve su id. V1: al empezar. V2 y V3: cuando el cliente elige el método. |
| `description` | `String` (`''`) | Texto que acompaña al pago (la glosa del QR) y se muestra con el monto. Algunos proveedores la exigen. |
| `descriptionFor` | `String Function(String orderId)?` | Arma la descripción cuando ya se conoce el `orderId`. Tiene prioridad sobre `description`. |
| `currency` | `String?` | Texto junto al monto (`'Bs'`). **Solo visual**: se cobra en la moneda de la cuenta. |

**Textos** (para traducir o adaptar)

| Parámetro | Por defecto | Versiones |
|---|---|---|
| `payLabel` | `'Pagar'` | V3: botón y título de la ventana. |
| `methodsTitle` | `'¿Con qué vas a pagar hoy?'` | V2 y V3: título de la lista. |
| `confirmLabel` | `'Confirmar'` | V2 y V3: botón del aviso antes del QR. |
| `backLabel` | `'Volver'` | V2 y V3: volver desde el aviso y botón "Volver" sin métodos. |
| `qrInstructionsTitle` | `'Prepárate para escanear'` | V2 y V3: título del aviso antes del QR. |
| `qrInstructionsMessage` | `'Tu código QR aparecerá…'` | V2 y V3: texto del aviso. |
| `cashInstructionsTitle` | `'Pagarás en caja'` | V2 y V3: título del aviso antes de crear el código de efectivo. |
| `cashInstructionsMessage` | `'Te daremos un código de pago…'` | V2 y V3: texto de ese aviso. |
| `cardInstructionsTitle` | `'Paga con tarjeta'` | V2 y V3: título del aviso antes de cobrar en el POS. |
| `cardInstructionsMessage` | `'Acerca, inserta o desliza tu tarjeta…'` | V2 y V3: texto de ese aviso. |

**Tiempos y tamaño**

| Parámetro | Por defecto | Qué es |
|---|---|---|
| `qrTimeout` | 5 min | Vida del QR y del temporizador. |
| `confirmTimeout` | 20 s | Cuánto verifica "Ya pagué" antes de avisar que el pago no llegó. |
| `pollInterval` | 3 s | Cada cuánto consulta el estado en segundo plano. |
| `successDelay` | 2 s | V3: cuánto se ve "¡Pago confirmado!" antes de cerrar la ventana. |
| `qrSize` | 240 | Tamaño máximo del QR. Se achica solo para entrar en la pantalla. |
| `autoOpen` | `false` | V3: abre la ventana al aparecer, sin mostrar el botón. |
| `autoSelectSingleMethod` | `true` | V2 y V3: si la cuenta tiene **un solo** método disponible, va directo a su cobro (sin lista ni aviso). Con más de uno, muestra la lista. |

**Callbacks** (ver [sección 9](#9-qué-significa-cada-callback))

`onSuccess`, `onCancel`, `onTimeout`, `onBack`, `onError`,
`onStatusChanged`, `onMethodSelected`, `onCashPayment` (efectivo, ver
[sección 10](#10-pago-en-efectivo)), `onCardPayment` (tarjeta, ver
[sección 11](#11-pago-con-tarjeta-pos)) y `onBackToMethods`.

**Tarjeta**

| Parámetro | Tipo | Qué es |
|---|---|---|
| `card` | `CardOptions?` | V2 y V3: activa la tarjeta en POS y dice con qué POS cobrar. Normalmente `CardOptions(terminalId: 'TOTEM100')`. Sin él la tarjeta no aparece. |
| `onCardPayment` | `ValueChanged<CardPayment>?` | El POS aprobó: es el `onSuccess` de la tarjeta. Obligatorio si pasas `card`. |

### Qué hace cada versión dentro de `PaymentFlow`

| Versión | Comportamiento |
|---|---|
| V1 | Muestra el QR de inmediato. Con `createOrderId`, primero "Preparando tu pago…"; si falla, "Reintentar" y "Cancelar". |
| V2 | Carga los métodos de la cuenta. Si hay **uno solo**, va directo a su QR; si hay varios, el cliente elige, aparece el aviso y luego el QR. |
| V3 | Muestra el botón "Pagar Bs 150.00" (o abre directo con `autoOpen`). La ventana muestra la lista, o directamente el QR si hay un solo método, y se cierra sola al pagar o al vencer. |

Con `onCashPayment`, V2 y V3 ofrecen además el efectivo si la cuenta lo tiene;
con `card`, la tarjeta en POS. V1 es solo QR.

---

## 6. V1 · `PaymentCheckout`

La app ya eligió QR; el SDK genera el QR y cobra.

```dart
PaymentCheckout(
  payments: payments,
  orderId: 'ORDER-123',
  amount: 150,
  currency: 'Bs',
  description: 'Pedido 123',
  autoStart: true,
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onCancel: () => Navigator.pop(context),
  onTimeout: () => Navigator.pop(context),
)
```

| Parámetro | Obligatorio | Por defecto | Qué hace |
|---|---|---|---|
| `payments` | sí | — | El `PaymentSdk`. |
| `amount` | sí | — | Monto a cobrar. |
| `orderId` | sí | — | Referencia única del pago. |
| `currency` | no | — | Texto junto al monto (solo visual). |
| `description` | no | `''` | Glosa del QR y texto bajo el monto. |
| `autoStart` | no | `false` | `true`: genera el QR al aparecer. `false`: muestra "Pagar con QR". |
| `qrTimeout` | no | 5 min | Vida del QR. |
| `confirmTimeout` | no | 20 s | Verificación de "Ya pagué". |
| `pollInterval` | no | 3 s | Consulta de estado. |
| `qrSize` | no | 240 | Tamaño máximo del QR. |
| `nextOrderId` | no | — | Devuelve un `orderId` nuevo al pedir otro QR. Sin él se reutiliza `orderId`. |
| `onNewQr` | no | — | Se llama en vez de regenerar al pedir otro QR (por ejemplo, para crear una orden nueva en tu sistema). |
| `onSuccess`, `onError`, `onStatusChanged`, `onCancel`, `onTimeout` | no | — | Ver [sección 9](#9-qué-significa-cada-callback). Sin `onCancel` no aparece "Cancelar"; sin `onTimeout` se ofrece "Generar nuevo QR". |

`nextOrderId` y `onNewQr` existen solo aquí. Con `PaymentFlow` en V1, "Generar
nuevo QR" reutiliza el mismo `orderId`.

---

## 7. V2 · `PaymentMethods`

El SDK muestra los métodos habilitados de la cuenta y cobra el elegido.

```dart
PaymentMethods(
  payments: payments,
  amount: 150,
  createOrderId: (method) => miBackend.crearOrden(),
  descriptionFor: (orderId) => 'Pedido $orderId',
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onTimeout: () => volver(),
  onBack: () => Navigator.pop(context),
)
```

| Parámetro | Obligatorio | Por defecto | Qué hace |
|---|---|---|---|
| `payments`, `amount` | sí | — | Igual que V1. |
| `orderId` / `createOrderId` | uno de los dos | — | La orden ya creada, o la función que la crea al elegir el método. |
| `description` / `descriptionFor` | no | `''` | Glosa del QR. |
| `currency` | no | — | Respaldo visual si la cuenta no informa moneda. |
| `title` | no | `'¿Con qué vas a pagar hoy?'` | Título de la lista. `null` lo oculta. |
| `confirmLabel`, `backLabel`, `qrInstructionsTitle`, `qrInstructionsMessage` | no | ver sección 5 | Textos. |
| `qrTimeout`, `confirmTimeout`, `pollInterval`, `qrSize` | no | 5 min / 20 s / 3 s / 240 | Igual que V1. |
| `autoSelectSingleMethod` | no | `true` | Con un solo método QR disponible, va directo a su cobro. |
| `cashInstructionsTitle`, `cashInstructionsMessage` | no | ver sección 5 | Aviso antes de crear el código de efectivo. |
| `onCashPayment` | no | — | Ofrece efectivo y avisa cuando el código existe. Ver [sección 10](#10-pago-en-efectivo). |
| `card`, `onCardPayment` | no | — | Ofrece tarjeta en POS y avisa cuando el POS aprobó. Ver [sección 11](#11-pago-con-tarjeta-pos). |
| `cardInstructionsTitle`, `cardInstructionsMessage` | no | ver sección 5 | Aviso antes de cobrar en el POS. |
| `onMethodSelected`, `onSuccess`, `onError`, `onStatusChanged`, `onTimeout`, `onCancel`, `onBack` | no | — | Ver [sección 9](#9-qué-significa-cada-callback). |

- Solo se muestran los métodos que esta versión del SDK sabe cobrar: QR,
  efectivo si pasas `onCashPayment` y tarjeta si pasas `card` (y su POS
  responde).
- **Un solo método:** la primera vez va directo a su QR. Si el cliente
  cancela, ve la lista (con ese método) en vez de generarse otro QR solo.
- `onCancel` en V2: el cliente canceló un QR (verificado sin pagar) y la vista
  ya volvió a la lista.

---

## 8. V3 · `PaymentSheet`

Abre la ventana de pago del SDK y devuelve cómo terminó.

```dart
final result = await PaymentSheet.show(
  context,
  payments: payments,
  amount: 150,
  orderId: 'ORDER-123',
  currency: 'Bs',
);

switch (result.status) {
  case PaymentSheetStatus.paid:        irAPantallaDeExito(result); // result.payment (QR) o result.cardPayment (tarjeta)
  case PaymentSheetStatus.expired:     mostrarAviso('El QR venció');
  case PaymentSheetStatus.cancelled:   break; // cerró sin pagar
  case PaymentSheetStatus.cashPending: irAPagaEnCaja(result.cashPayment!); // solo con acceptCash
}
```

| Parámetro | Obligatorio | Por defecto | Qué hace |
|---|---|---|---|
| `context` | sí | — | El `BuildContext` desde donde se abre. |
| `payments`, `amount` | sí | — | Igual que V1. |
| `orderId` / `createOrderId` | uno de los dos | — | Igual que V2. |
| `description` / `descriptionFor`, `currency` | no | — | Igual que V2. |
| `title` | no | `'Pagar'` | Texto sobre el monto en el encabezado. |
| `methodsTitle` | no | `'¿Con qué vas a pagar?'` | Título de la lista. |
| `confirmLabel`, `backLabel`, `qrInstructionsTitle`, `qrInstructionsMessage` | no | ver sección 5 | Textos. |
| `qrTimeout`, `confirmTimeout`, `pollInterval`, `qrSize` | no | 5 min / 20 s / 3 s / 240 | Igual que V1. |
| `successDelay` | no | 2 s | Cuánto se ve "¡Pago confirmado!" antes de cerrar. |
| `autoSelectSingleMethod` | no | `true` | Con un solo método QR disponible, la ventana abre directo en su QR. |
| `acceptCash` | no | `false` | Ofrece efectivo si la cuenta lo tiene. Ver [sección 10](#10-pago-en-efectivo). |
| `cashInstructionsTitle`, `cashInstructionsMessage` | no | ver sección 5 | Aviso antes de crear el código de efectivo. |
| `card` | no | — | Ofrece tarjeta en POS. Ver [sección 11](#11-pago-con-tarjeta-pos). |
| `cardInstructionsTitle`, `cardInstructionsMessage` | no | ver sección 5 | Aviso antes de cobrar en el POS. |
| `onMethodSelected`, `onError`, `onStatusChanged` | no | — | Ver [sección 9](#9-qué-significa-cada-callback). |

**Resultado (`PaymentSheetResult`):** `status` (`paid`, `expired`,
`cancelled` o `cashPending`), `payment` (el pago QR confirmado), `cardPayment`
(el pago con tarjeta aprobado; con `paid` viene uno de los dos),
`cashPayment` (el código, solo con `cashPending`), `method` (el método
elegido), `isPaid` e `isCashPending`.

Desde la 0.5.0 `PaymentSheetStatus` tiene `cashPending`: si haces un `switch`
exhaustivo sobre `result.status`, agrégale ese caso (sin `acceptCash` nunca
llega).

- Pantallas de menos de 600 px: sube desde abajo. Desde 600 px: ventana
  centrada.
- Tocar afuera o arrastrar no la cierra. Al cerrar con un QR en pantalla,
  verifica primero: si ya estaba pagado devuelve `paid`.
- Si no hay métodos para pagar, muestra "Volver", que la cierra como
  `cancelled`.
- Mientras el POS está cobrando, la ventana **no se cierra** (el POS no se
  puede cancelar desde la app).

---

## 9. Qué significa cada callback

| Callback | Cuándo se llama | V1 | V2 | V3 |
|---|---|---|---|---|
| `onSuccess(QrPayment)` | Una vez, cuando el pago queda confirmado. | ✅ | ✅ | ✅ (`PaymentFlow`) / `paid` (`PaymentSheet`) |
| `onCancel()` | El cliente sale sin pagar, después de verificar que no pagó. En V1 también hace aparecer el botón "Cancelar". | ✅ | ✅ | ✅ (`PaymentFlow`) / `cancelled` |
| `onTimeout()` | El QR venció sin pago (unos segundos después de "Tiempo agotado"). | ✅ | ✅ | ✅ (`PaymentFlow`) / `expired` |
| `onBack()` | No hay con qué pagar (los métodos no cargaron o no hay ninguno) y el cliente toca "Volver". Opcional: si no lo pasas, no aparece el botón. | — | ✅ | La ventana lo muestra siempre y se cierra como cancelada |
| `onError(PaymentSdkException)` | En cada error (al generar o al consultar). La vista ya lo muestra; úsalo para registrar. | ✅ | ✅ | ✅ |
| `onStatusChanged(PaymentStatus)` | Cada cambio de estado del QR. | ✅ | ✅ | ✅ |
| `onMethodSelected(PaymentMethodInfo)` | El cliente confirmó un método, antes de crear la orden. | — | ✅ | ✅ |
| `onCashPayment(CashPayment)` | El código de efectivo ya existe: la orden queda pendiente de pago en caja. Pasarlo es lo que activa el efectivo. | — | ✅ | ✅ (`PaymentFlow`) / `cashPending` (`PaymentSheet` con `acceptCash`) |
| `onBackToMethods()` | La lista de métodos vuelve a verse después de elegir uno (QR cancelado, tarjeta rechazada, "Otro método"…). Úsalo para reactivar lo que tu pantalla bloquea mientras se cobra. | — | ✅ | — (la ventana avisa `onCancel` al cerrarse) |
| `onCardPayment(CardPayment)` | El POS aprobó el pago con tarjeta. Trae autorización, últimos 4 y red para el comprobante. | — | ✅ | ✅ (`PaymentFlow`, al cerrar la ventana) / `paid` con `cardPayment` |

**Importante:** no despaches un pedido solo por `onSuccess`. Confirma el pago
también desde tu servidor.

---

## 10. Pago en efectivo

El cliente elige **"Pago en efectivo"**, recibe un **código** (por ejemplo
`EF-7K3M9QX2`) y lo presenta en caja. El pedido queda **pendiente** hasta que
el cajero registra el cobro o lo cancela: el código **no vence**.

- **Es opcional por app.** El SDK solo ofrece efectivo si tu app lo maneja:
  `onCashPayment` en `PaymentFlow` o `PaymentMethods`, o `acceptCash: true` en
  `PaymentSheet.show`. Sin eso no aparece, aunque la cuenta lo tenga
  habilitado.
- **La cuenta debe tenerlo habilitado** en Nexus Payments.
- **Nunca se elige solo:** aunque sea el único método, el cliente lo toca y
  confirma el aviso "Pagarás en caja" (deja un pedido pendiente).
- **Con el código en pantalla no hay "Volver":** el pedido ya existe.
- **Pedirlo otra vez** para el mismo `orderId` pendiente devuelve el mismo
  código, así que "Reintentar" nunca duplica el pago.
- En `createOrderId(method)`, `method.isCash` te dice que la orden es en
  efectivo.

| Versión | Qué pasa |
|---|---|
| V1 | Solo QR. |
| V2 | Muestra el código y llama `onCashPayment(CashPayment)`. La vista sigue mostrando el código: sal cuando quieras, igual que después de `onSuccess`. |
| V3 | Muestra el código con un botón "Listo". "Listo" o cerrar la ventana devuelve `cashPending` con `result.cashPayment`; con `PaymentFlow` se llama `onCashPayment`. |

```dart
PaymentFlow(
  version: PaymentVersion.v2,
  payments: payments,
  amount: carrito.total,
  createOrderId: (method) async {
    final orden = await miBackend.crearOrdenPendiente(carrito, efectivo: method.isCash);
    return orden.id;
  },
  descriptionFor: (orderId) => 'Pedido $orderId',
  onSuccess: (payment) => irAPantallaDeExito(payment),
  onCashPayment: (cash) {
    imprimirTicket(codigo: cash.code, monto: cash.amount);
    irAPantallaPagaEnCaja(cash); // muestra cash.code
  },
)
```

**Saber si ya se cobró:** `payments.getCashPaymentStatus(orderId)` devuelve
`pending`, `paid` o `cancelled`. Tu servidor también recibe la notificación de
la cuenta cuando se cobra o se cancela; despacha solo cuando el pago esté
confirmado.

---

## 11. Pago con tarjeta (POS)

El cliente elige **"Tarjeta"** y paga en un **POS Bancard** que está en la
misma red que el equipo (un totem, una caja de parqueo…). El SDK registra el
pago en Nexus Payments, le pide el cobro al POS, espera a que el cliente
termine allí y registra lo que el POS respondió.

### Qué hace falta

1. **La cuenta con tarjeta habilitada** en Nexus Payments (método `CARD`).
2. **El equipo registrado como terminal** en Nexus Payments, con un código
   (el IMEI del totem, `PARKING-CAJA-1`…), la IP y el puerto del POS y la
   forma de conexión:

| Conexión | Cómo llega el SDK al POS | En el equipo |
|---|---|---|
| `BRIDGE` | Por el servicio local **API POS Bancard** (`http://127.0.0.1:8000`), que reenvía el cobro al POS. | El servicio instalado y corriendo. |
| `DIRECT` | Directo al POS (`http://IP:PUERTO/sale`). | Nada más. |

3. **El POS con IP fija** (reserva DHCP en el router o IP estática) y en la
   misma red que el equipo.

Cambiar la IP del POS, o pasar un equipo de `BRIDGE` a `DIRECT`, es editar el
terminal en Nexus Payments: la app no cambia y el cambio aplica en el
siguiente pago.

### En la app: una línea

```dart
PaymentFlow(
  version: PaymentVersion.v2,
  payments: payments,
  amount: carrito.total,
  createOrderId: (method) => miBackend.crearOrden(carrito),
  card: const CardOptions(terminalId: 'TOTEM100'), // el código del equipo
  onCardPayment: (card) {
    imprimirComprobante(
      autorizacion: card.authCode,
      tarjeta: card.maskedCard, // "VISA •••• 1234"
      boleta: card.receiptNumber,
    );
    irAPantallaDeExito();
  },
  onSuccess: (qr) => irAPantallaDeExito(),
)
```

- **Es opcional por equipo.** Sin `card` la tarjeta no aparece, aunque la
  cuenta la tenga. Un celular o un equipo sin POS simplemente no lo pasa.
- **Se oculta sola si no hay con qué cobrar:** si el terminal no está
  registrado o el POS (o el servicio local) no responde, la tarjeta no se
  muestra. `checkReachability: false` desactiva esa comprobación.
- **Nunca se elige sola**, aunque sea el único método: inicia un cobro en el
  POS.
- **Mientras el POS cobra no hay "Volver"**: el POS no se puede cancelar desde
  la app.
- En `createOrderId(method)`, `method.isCard` te dice que la orden es con
  tarjeta.

| Versión | Qué pasa |
|---|---|
| V1 | Solo QR. |
| V2 | "Sigue las instrucciones del POS" y luego "¡Pago aprobado!"; llama `onCardPayment(CardPayment)`. Sal cuando quieras, igual que después de `onSuccess`. |
| V3 | Lo mismo dentro de la ventana, que se cierra sola al aprobar: `paid` con `result.cardPayment`; con `PaymentFlow` se llama `onCardPayment`. |

### Cómo termina un cobro

| Resultado | Qué ve el cliente | ¿Se cobró? | Qué puede hacer |
|---|---|---|---|
| Aprobado | "¡Pago aprobado!" con la tarjeta y la autorización | Sí | — (`onCardPayment`) |
| Rechazado | "Tarjeta rechazada" con el motivo del POS | No | Reintentar u Otro método |
| POS sin conexión | "No pudimos comunicarnos con el POS" | No | Reintentar o Volver |
| No se pudo registrar | "No pudimos iniciar el cobro" | No (el POS no se tocó) | Reintentar o Volver |
| Respuesta perdida | "No pudimos confirmar el cobro" | **Quizás** | Solo "Entendido": el SDK **nunca** reintenta, para no cobrar dos veces. El pago queda pendiente en Nexus Payments para revisarlo contra el POS. |

`onError` recibe un `CardTerminalException` cuando falla el POS: su
`outcomeUnknown` es `true` solo en el último caso.

### Otras formas de configurar el POS

```dart
// El POS configurado en la app (pruebas, un equipo aún no registrado):
card: const CardOptions.manual(CardTerminalConfig(
  posIp: '192.168.0.34',
  posPort: 3000,
  connection: CardConnection.direct, // o bridge
)),

// Tu propio CardTerminal (otra marca de POS, un simulador):
card: CardOptions.custom(MiTerminal()),
```

**Saber si ya se cobró:** `payments.getCardPaymentStatus(orderId)` devuelve
`pending`, `paid` o `failed`. Tu servidor también recibe la notificación de la
cuenta (proveedor `CARD`) cuando el pago queda aprobado o rechazado.

---

## 12. Ejemplos completos

### La orden ya existe (por ejemplo, la crea tu backend antes de cobrar)

```dart
class PagoPage extends StatefulWidget {
  const PagoPage({super.key, required this.orden, required this.version});

  final Orden orden;
  final PaymentVersion version;

  @override
  State<PagoPage> createState() => _PagoPageState();
}

class _PagoPageState extends State<PagoPage> {
  late final Future<PaymentSdk> _payments = _cargarSdk();

  Future<PaymentSdk> _cargarSdk() async {
    final creds = await miBackend.obtenerCredencialesDePago(widget.orden.comercioId);
    return PaymentSdk(
      config: PaymentSdkConfig(baseUrl: creds.baseUrl, apiKey: creds.apiKey),
    );
  }

  @override
  void dispose() {
    _payments.then((sdk) => sdk.dispose(), onError: (_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<PaymentSdk>(
        future: _payments,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('No se pudo preparar el pago'));
          final payments = snapshot.data;
          if (payments == null) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PaymentFlow(
              version: widget.version,
              payments: payments,
              amount: widget.orden.total,
              orderId: widget.orden.id,
              currency: 'Bs',
              description: 'Pedido ${widget.orden.id}',
              onSuccess: (payment) => Navigator.pop(context, true),
              onCancel: () => Navigator.pop(context, false),
              onTimeout: () => Navigator.pop(context, false),
              onBack: () => Navigator.pop(context, false),
            ),
          );
        },
      ),
    );
  }
}
```

### La orden se crea cuando el cliente elige el método

```dart
PaymentFlow(
  version: PaymentVersion.v3,
  payments: payments,
  amount: carrito.total,
  createOrderId: (method) async {
    final orden = await miBackend.crearOrdenPendiente(carrito);
    return orden.id;
  },
  descriptionFor: (orderId) => 'Pedido $orderId',
  onSuccess: (payment) => miBackend.completarOrden(payment.paymentId),
  onCancel: () {},
)
```

Si `createOrderId` lanza un error, el SDK muestra "No se pudo preparar el
pago" y deja reintentar.

---

## 13. Sin interfaz: `PaymentSdk`, modelos y widgets sueltos

Para armar una pantalla propia o cobrar sin los componentes del SDK.

| Método | Devuelve | Qué hace |
|---|---|---|
| `generateQr({orderId, amount, description = '', dueDate?})` | `QrPayment` | Crea el pago y su QR. Valida antes de enviar (`orderId` no vacío, `amount` > 0, `dueDate` futura). |
| `getPaymentStatus(orderId)` | `PaymentStatus` | Estado actual, por `orderId`. Una orden desconocida se informa como `pending`. |
| `watchPaymentStatus(orderId, {interval = 3 s, timeout = 15 min})` | `Stream<PaymentStatus>` | Emite solo cambios y se cierra en un estado final. Sigue tras errores reintentables. |
| `getPayment(paymentId)` | `QrPayment` | El pago guardado, sin consultar al proveedor. |
| `getPaymentMethods()` | `List<PaymentMethodInfo>` | Métodos habilitados de la cuenta, en orden. |
| `createCashPayment({orderId, amount, description = ''})` | `CashPayment` | Crea el pago en efectivo y su código. El mismo `orderId` pendiente devuelve el mismo código. Si la cuenta no tiene efectivo: `ValidationException`. |
| `getCashPaymentStatus(orderId)` | `PaymentStatus` | Estado del pago en efectivo: `pending`, `paid` o `cancelled`. Orden desconocida: `PaymentNotFoundException`. |
| `getCardTerminal(terminalId)` | `CardTerminalConfig` | Cómo llegar al POS del terminal registrado. Desconocido o inactivo: `PaymentNotFoundException`. |
| `resolveCardTerminal(CardOptions)` | `CardTerminal` | El terminal listo para cobrar según las opciones. |
| `chargeCard({terminal, orderId, amount, description, terminalId, onPosStarted})` | `CardPayment` | El cobro completo para pantallas propias: registra, cobra en el POS y registra el resultado (aprobado o rechazado). Errores: ver sección 11. |
| `createCardPayment({orderId, amount, description, terminalId})` | `CardPayment` | Registra el pago antes de cobrar. Una orden ya cobrada con tarjeta: `BackendException` (409). |
| `reportCardResult(id, CardChargeResult)` | `CardPayment` | Registra lo que respondió el POS. Repetirlo no cambia nada. |
| `getCardPaymentStatus(orderId)` | `PaymentStatus` | Estado del último pago con tarjeta: `pending`, `paid` o `failed`. |
| `dispose()` | — | Cierra las conexiones. |

```dart
final qr = await payments.generateQr(orderId: 'ORDER-123', amount: 150);
// muestra PaymentQrView(payment: qr)

final sub = payments.watchPaymentStatus('ORDER-123').listen((status) {
  if (status == PaymentStatus.paid) { /* listo */ }
});
// … sub.cancel() al salir
```

### Modelos

| Modelo | Campos |
|---|---|
| `QrPayment` | `paymentId`, `qrImageBase64` (PNG en Base64), `qrImageBytes` / `hasQrImage`, `status`, `dueDate`. |
| `CashPayment` | `code`, `orderId`, `amount`, `currency`, `status`, `description`, `createdAt`, `isPending`. |
| `CardPayment` | `id`, `orderId`, `amount`, `currency`, `status`, `terminalId`, `authCode`, `receiptNumber`, `last4`, `bin`, `cardNetwork`, `entryLabel`, `message`, `maskedCard`, `isApproved`, `isRejected`, `recorded` (`false` si el POS respondió pero Nexus Payments no pudo registrarlo). |
| `CardOptions` | `CardOptions(terminalId:)`, `.manual(CardTerminalConfig)`, `.custom(CardTerminal)`; `checkReachability`. |
| `CardTerminalConfig` | `code`, `name`, `connection` (`bridge`/`direct`), `posIp`, `posPort`, `bridgeUrl`. |
| `CardTerminal` | `isReachable()`, `charge(...)`. Implementaciones: `BancardBridgeTerminal`, `BancardDirectTerminal`. |
| `PaymentStatus` | `pending`, `paid`, `failed` (también tarjeta rechazada), `expired`, `cancelled` (solo efectivo) y `unknown` (un estado nuevo que esta versión no conoce). `isFinal` indica si ya no cambiará. |
| `PaymentMethodInfo` | `code` (`QR`, `EFECTIVO`, `CARD`…), `name`, `description`, `iconUrl`, `currency`, `position`, `isQr`, `isCash`, `isCard`, `isSupported`. |
| `PaymentVersion` | `v1`, `v2`, `v3`; `tryParse(String?)` y `label`. |

### Widgets sueltos

| Widget | Parámetros | Muestra |
|---|---|---|
| `PaymentQrView` | `payment`, `size` (240), `unavailableText` | La imagen del QR o "QR no disponible". |
| `PaymentStatusView` | `status`, `labels` | Ícono y texto del estado (textos cambiables). |

**Probar tu app sin backend:** `PaymentSdk` acepta `httpClientAdapter` (un
`HttpClientAdapter` de `dio`) para simular las respuestas.

---

## 14. Errores

Todo error es un `PaymentSdkException` con `message`, `statusCode`, `details`
e `isRetryable`. Los componentes ya los muestran; para manejarlos tú, usa
`onError` o un `try/catch` con `PaymentSdk`.

| Excepción | Cuándo | ¿Reintentable? |
|---|---|---|
| `NetworkException` | Sin conexión, DNS, TLS | sí |
| `RequestTimeoutException` | Se superó `timeout` | sí |
| `AuthenticationException` | 401/403: API key ausente, inválida o sin permiso | no |
| `ValidationException` | 400/422, o datos inválidos detectados antes de enviar | no |
| `PaymentNotFoundException` | 404 | no |
| `ProviderException` | 503: falló el proveedor de pagos | sí |
| `RateLimitException` | 429 | sí |
| `BackendException` | Otros 5xx o respuesta inesperada | sí si es 5xx |
| `StatusWatchTimeoutException` | `watchPaymentStatus` superó su `timeout` | no |
| `CardTerminalException` | Falló el POS o el servicio local. `outcomeUnknown`: si es `true`, el cobro pudo haberse hecho | sí solo si `outcomeUnknown` es `false` |

---

## 15. Lista de verificación

- [ ] Flutter 3.24 o superior.
- [ ] Dependencia por `git` con un `ref` de tag; `pubspec.lock` commiteado.
- [ ] Permisos de red (Android/macOS).
- [ ] La API key llega desde tu backend, no está en el código.
- [ ] Un `PaymentSdk` por comercio, con `dispose()` al terminar.
- [ ] `orderId` único por pago (o `createOrderId`).
- [ ] `description` o `descriptionFor` con texto (algunos proveedores exigen glosa).
- [ ] `onSuccess`, `onCancel` y `onTimeout` llevan al cliente a la pantalla correcta.
- [ ] V2: `onBack` si tu pantalla no tiene otro botón de volver.
- [ ] V2/V3: el backend tiene `GET /api/payment-methods`.
- [ ] Efectivo: `onCashPayment` (o `acceptCash`) muestra el código al cliente y tu sistema deja la orden pendiente de pago en caja.
- [ ] Tarjeta: el equipo está registrado como terminal, el POS tiene IP fija, `card` lleva su código y `onCardPayment` imprime el comprobante.
- [ ] Tu servidor confirma el pago antes de despachar.

---

## 16. Problemas comunes

| Síntoma | Causa | Solución |
|---|---|---|
| `Cannot GET /api/payment-methods` en V2/V3 | El backend al que apunta la cuenta no tiene el endpoint de métodos. | Usa un backend que lo tenga, o V1 (no lo necesita). |
| `AuthenticationException` | API key incorrecta o de otra cuenta/entorno. | Revisa la key y que `baseUrl` sea del mismo entorno. |
| "dueDate must be greater than the current time" | El reloj del dispositivo está atrasado. | Corrige la hora del dispositivo (en emuladores, reinícialo). |
| El proveedor rechaza la glosa | `description` vacía. | Pasa `description` o `descriptionFor`. |
| `pub get` no toma la versión nueva | El `ref` sigue en el tag anterior. | Cambia el `ref` y corre `flutter pub get`. |
| `Repository not found` al instalar | La máquina no tiene acceso al repositorio. | Revisa la URL y el acceso a GitHub. |
| "No hay métodos de pago disponibles" | La cuenta no tiene métodos activos. | Actívalos en Nexus Payments. |
| No aparece "Pago en efectivo" | Tu app no pasa `onCashPayment` (o `acceptCash`), o la cuenta no lo tiene habilitado. | Pásalo y pide que lo habiliten en Nexus Payments. |
| "El pago en efectivo no está habilitado para este comercio" | La cuenta no tiene efectivo configurado. | Pide que lo habiliten en Nexus Payments. |
| No aparece "Tarjeta" | Falta `card`, la cuenta no tiene `CARD`, el terminal no está registrado o activo, o el POS / el servicio local no responde. | Con `enableLogging: true` el SDK imprime por qué la ocultó. Revisa el terminal, la IP del POS y que el servicio esté corriendo. |
| "No pudimos comunicarnos con el POS" | El POS está apagado, cambió de IP o no está en la misma red. | Revisa el POS y la IP del terminal en Nexus Payments. |
| "El pago con tarjeta no está habilitado para este comercio" | La cuenta no tiene `CARD` configurado. | Pide que lo habiliten en Nexus Payments. |
