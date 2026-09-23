# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyecto

YogurLac es una app de gestión en español (es-AR, moneda ARS) para un negocio de lácteos: ventas, clientes, listas de precios y proveedores. Es un **sitio estático sin paso de build**: páginas HTML + JS vanilla, Tailwind por CDN y Supabase (Postgres) consumido directamente desde el navegador. No hay package.json, bundler, linter ni tests.

## Cómo ejecutar

Abrir cualquier `.html`, o servir la raíz con un servidor estático (p. ej. `python -m http.server`). Las páginas necesitan red para los CDN de Tailwind y `@supabase/supabase-js`, y para el backend de Supabase.

## Arquitectura

- **Una página = un HTML + un JS** (`index.html`↔`js/dashboard.js`, `ventas.html`↔`js/ventas.js`, `clientes.html`↔`js/clientes.js`, `precios.html`↔`js/precios.js`, `proveedores.html`↔`js/proveedores.js`). Cada HTML carga primero `js/supabase.js` y después el script de su página.
- `js/supabase.js` crea el cliente compartido como `window.supabaseClient` (URL y anon key hardcodeadas). Todo el acceso a datos va por `window.supabaseClient.from(...)` directamente en los scripts de cada página; no hay capa de API ni de servicios.
- La navbar (escritorio + menú móvil) está **copiada y pegada en cada HTML**: agregar o renombrar una página implica editar la nav en todos, incluido el estilo del link activo y el toggle del menú móvil en el script de cada página.
- El renderizado es imperativo: los scripts arman filas con `innerHTML` / `createElement` y usan handlers `onclick=` inline, por eso las funciones se cuelgan de `window` (`window.guardarPrecioInline = ...`). Mantener ese patrón al agregar acciones por fila. Cada página guarda una caché a nivel de módulo (p. ej. `productosCache` en `precios.js` y `ventas.js`) y vuelve a renderizar desde ella.
- `formatCurrency` (`Intl.NumberFormat` es-AR / ARS) está duplicada en cada script en lugar de compartirse.
- Los textos de UI, comentarios e identificadores están en español.

## Modelo de datos y listas de precios

- El esquema está en `supabase-schema.sql` (se ejecuta a mano en el SQL editor de Supabase). Ver "Autenticación y RLS" más abajo.
- Los clientes tienen `lista_precio` (`minorista` | `mayorista` | `distribuidor`); los productos tienen `precio_minorista` / `precio_mayorista` / `precio_distribuidor`, con `precio_venta` como respaldo. `ventas.js` elige el precio según la lista del cliente; `precios.js` los edita en línea (guarda al perder foco o con Enter).
- Las ventas se registran con la función `registrar_venta(cliente_id, items)` (RPC, SECURITY INVOKER): en una transacción crea la venta, sus detalles y suma el total al `saldo`; los precios los calcula el servidor según la lista del cliente y rechaza productos inactivos. `ventas.js` solo la invoca. Los movimientos manuales de saldo (compra a cuenta / pago) usan `registrar_movimiento_cliente(cliente_id, tipo, monto, concepto)`, y tanto las ventas como esos movimientos quedan en el historial `movimientos_cliente` (el saldo de `clientes` es la suma de sus movimientos). Cualquier cambio de saldo debe pasar por una de estas dos funciones, no por un `update` directo desde el navegador.

## Esquema y seguridad (estado actual)

`supabase-schema.sql` es el esquema completo de la base actual (proyecto Supabase `jklsoynymbpwvlaqwzhy`, cuenta nueva, región sa-east-1; aplicado el 2026-09-23 como migración `schema_inicial`), no un script incremental. Los tres archivos de `supabase/migrations/` fechados 20260923 son del proyecto original ya migrado: referencia histórica, no se vuelven a aplicar. Si se cambian tablas en Supabase, actualizar ese archivo. La base real es la fuente de verdad.

`productos.precio_venta` es NOT NULL (el formulario de precios lo exige).

## Autenticación y RLS

La app la usan solo 2 dueños. Login con Supabase Auth (email + contraseña, registro público desactivado en el panel). `js/auth.js` se carga en todas las páginas, las oculta hasta verificar sesión y redirige a `login.html`; toda página nueva debe incluir `<style id="auth-oculto">body{visibility:hidden}</style>` en el `<head>` y `js/auth.js` justo después de `js/supabase.js`. Eso solo protege la interfaz: los datos los protege RLS, con la política `"Solo duenos"` (`es_dueno()`, que consulta la tabla `duenos`) en todas las tablas. Un usuario nuevo de Auth no ve nada hasta agregarlo a `duenos`. Los cambios de base van como migraciones en `supabase/migrations/` (nombradas con la versión que asigna Supabase al aplicarlas).