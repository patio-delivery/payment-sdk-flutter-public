# payment_sdk_flutter

SDK Flutter de **Nexus Payments**. Una app lo agrega como dependencia y, con
un componente, puede cobrar con QR: generar el QR, mostrarlo con un
temporizador, detectar el pago y enterarse del resultado. También puede
mostrar los métodos de pago que la cuenta tiene habilitados.

```text
Tu app Flutter ──► payment_sdk_flutter ──► Nexus Payments ──► Proveedor de pagos
```

El SDK **solo habla con Nexus Payments**. La app dice "quiero cobrar Bs 150" y
Nexus Payments decide con qué proveedor, en qué moneda y a qué cuenta, según la
API key. Nexus Payments es la fuente de verdad del estado de cada pago.

| Documento | Para qué |
|---|---|
| **Este README** | De qué trata el SDK: qué incluye, sus versiones y cómo funciona. |
| **[doc/INTEGRACION.md](doc/INTEGRACION.md)** | Cómo integrarlo en tu proyecto: requisitos, instalación y parámetros de cada versión, con ejemplos. |
| [CHANGELOG.md](CHANGELOG.md) | Qué cambió en cada versión. |

## Contenido

1. [Qué incluye](#1-qué-incluye)
2. [Las versiones (V1, V2, V3)](#2-las-versiones-v1-v2-v3)
3. [Cómo funciona](#3-cómo-funciona)
4. [Pantallas](#4-pantallas)
5. [Integrarlo en tu proyecto](#5-integrarlo-en-tu-proyecto)
6. [Tests](#6-tests)
7. [Seguridad](#7-seguridad)
8. [Limitaciones](#8-limitaciones)

---

## 1. Qué incluye

| Pieza | Qué es |
|---|---|
| **`PaymentFlow`** | Un solo componente para todas las versiones: integras una vez y eliges la versión con `PaymentVersion`. |
| **`PaymentCheckout`** (V1) | Cobro QR directo, para apps que ya tienen su pantalla de métodos. |
| **`PaymentMethods`** (V2) | Lista de métodos habilitados de la cuenta y cobro del elegido, dentro de tu pantalla. |
| **`PaymentSheet`** (V3) | Ventana de pago propia del SDK que devuelve cómo terminó. |
| **`PaymentSdk`** | API sin interfaz: generar QR, consultar y escuchar el estado, listar métodos. |
| **Modelos y errores** | `QrPayment`, `PaymentStatus`, `PaymentMethodInfo`, `PaymentVersion` y la jerarquía `PaymentSdkException`. |
| **Widgets sueltos** | `PaymentQrView` (la imagen del QR) y `PaymentStatusView` (ícono y texto de un estado). |

Depende solo de `dio` (HTTP) y `clock` (hora testeable). No usa librerías de
QR, animación ni estado, así que no impone arquitectura a tu app.

---

## 2. Las versiones (V1, V2, V3)

| Versión | Tu app dibuja | El SDK dibuja |
|---|---|---|
| **V1 · Direct Payment** | Carrito, total **y sus métodos de pago** | El cobro QR, cuando la app ya eligió QR |
| **V2 · Embedded Methods** | Carrito y total | **Los métodos habilitados de la cuenta** y el cobro |
| **V3 · Payment Sheet** | Carrito y botón "Pagar" | **Su propia ventana** con los métodos y el cobro |

```text
V1:  App ─ "el cliente eligió QR" ─► SDK genera y cobra el QR
V2:  App ─ "quiero cobrar Bs 150" ─► SDK consulta qué métodos tiene la cuenta
                                    ─► los muestra ─► el cliente elige ─► SDK cobra
V3:  App ─ botón "Pagar" ─► SDK abre su ventana (métodos + cobro) ─► devuelve el resultado
```

Las versiones se identifican como `PaymentVersion.v1`, `v2` y `v3`, y se
pueden elegir desde configuración (`'v1'`, `'v2'`, `'v3'` u `'off'`). Con
`PaymentFlow`, cambiar de versión no requiere tocar código.

---

## 3. Cómo funciona

### 3.1 Capas

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Componentes públicos    PaymentFlow (todas) · PaymentCheckout (V1) ·  │
│                         PaymentMethods (V2) · PaymentSheet (V3)        │
├──────────────────────────────────────────────────────────────────────┤
│ UI compartida (interna) métodos · tarjeta de cobro · QR · animaciones │
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

- **Una sola lógica de pago:** todas las versiones comparten el mismo ciclo de
  vida, así que el temporizador, la consulta de estado y "Ya pagué" se
  comportan igual.
- **Lo público es poco:** tu app solo importa
  `package:payment_sdk_flutter/payment_sdk_flutter.dart`. Lo interno puede
  cambiar sin romper apps.

### 3.2 Vida de un pago QR

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
- **El estado se obtiene consultando** a Nexus Payments. Tu app no necesita
  recibir webhooks.
- **`orderId` es la referencia del pago y debe ser única.**

### 3.3 Estados que ve el cliente

| Estado | Qué se muestra | Botones |
|---|---|---|
| Generando | "Generando tu código QR…" | — |
| Esperando pago | QR, "Escanea el código…", **temporizador** | **Ya pagué**, Cancelar |
| Verificando | "Verificando tu pago…" | — |
| Pagado | ✓ "¡Pago confirmado!" | — |
| Rechazado | ✗ "Pago rechazado" | Generar nuevo QR, Cancelar |
| Tiempo agotado | "Tiempo agotado" | Generar nuevo QR (si la app no maneja `onTimeout`) |
| Error al generar | "No pudimos generar el QR" + motivo | Reintentar, Cancelar |
| Un solo método (V2/V3) | Directo el QR de ese método, sin lista | Igual que "Esperando pago" |
| Sin métodos (V2/V3) | El error o "No hay métodos de pago disponibles" | Reintentar, **Volver** |

### 3.4 Tiempos y reglas

| Regla | Por defecto |
|---|---|
| Vida del QR (temporizador y vencimiento) | 5 min |
| Consulta de estado en segundo plano | cada 3 s |
| "Ya pagué": verifica activamente | cada 2 s durante 20 s |
| Aviso "Aún no recibimos tu pago" | 8 s |
| Salida tras "Tiempo agotado" | 4 s |

- **Al llegar a cero** el SDK consulta una última vez: un pago hecho en el
  último segundo cuenta.
- **"Ya pagué" sin pago** vuelve al QR con el tiempo que quedaba.
- **Cancelar o cerrar** verifica antes de salir: si el QR ya estaba pagado,
  reporta éxito en lugar de cancelar.

---

## 4. Pantallas

Las vistas se adaptan a cualquier pantalla:

| Clase | Cuándo | Ejemplos |
|---|---|---|
| compacta | ancho < 360 o alto < 500 | celulares chicos, celulares en horizontal |
| normal | el resto | celulares, tablets |
| grande | lado más corto ≥ 900 | kioscos, tablets grandes, escritorio |

- **El QR** se achica para entrar en el ancho y en menos de la mitad del alto.
- **Tarjeta, loaders, botones y tarjetas de métodos** cambian de tamaño según
  la pantalla; los métodos van en 1 o 2 columnas.
- **Diálogos y la ventana de V3** se desplazan si la pantalla es baja.
- **Montos largos** se reducen en lugar de desbordar, también con texto grande.

---

## 5. Integrarlo en tu proyecto

Requisitos, instalación, parámetros de cada versión y ejemplos completos:
**[doc/INTEGRACION.md](doc/INTEGRACION.md)**.

En resumen:

```yaml
dependencies:
  payment_sdk_flutter:
    git:
      url: https://github.com/patio-delivery/payment-sdk-flutter-public.git
      ref: v0.4.1
```

```dart
PaymentFlow(
  version: PaymentVersion.tryParse(config)!,   // 'v1', 'v2' o 'v3'
  payments: PaymentSdk(config: PaymentSdkConfig(baseUrl: url, apiKey: key)),
  amount: 150,
  orderId: 'ORDER-123',
  onSuccess: (payment) => ...,
  onCancel: () => ...,
  onTimeout: () => ...,
)
```

---

## 6. Tests

```bash
flutter pub get
flutter analyze
flutter test
```

Las pruebas no usan un servidor real: las respuestas HTTP se simulan con
`test/helpers/fake_adapter.dart`. Cubren el núcleo, cada versión, `PaymentFlow`
y las vistas en 6 tipos de pantalla.

---

## 7. Seguridad

- La key solo viaja en `Authorization: Bearer`. El SDK no la imprime, no la
  guarda en disco y la oculta en `toString`.
- Entrega la key desde tu backend; no la incluyas en el código de la app.
- **No confíes solo en `onSuccess` para despachar un pedido:** confirma el pago
  también desde tu servidor.
- Usa `https` fuera de desarrollo.

---

## 8. Limitaciones

- **Solo QR por ahora.** V2 y V3 ya están preparadas para más métodos: cuando
  estén disponibles aparecerán sin cambiar las apps.
- **Textos por defecto en español** (configurables en V2, V3 y `PaymentFlow`).
