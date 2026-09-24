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
- `js/utils.js` (cargado después de `js/auth.js` en cada página menos el login) define `escapeHtml()`. **Todo texto escrito por un usuario (nombres, teléfono, dirección, concepto, etc.) que se inserte con `innerHTML` debe pasar por `escapeHtml()`**, o bien usarse con `textContent`. Los botones con `onclick=` inline reciben solo el id (UUID) y la función busca el resto en la caché de la página (`clientesPorId` en `clientes.js`, `productosCache` en `precios.js`); nunca se interpolan nombres dentro del atributo.
- Los textos de UI, comentarios e identificadores están en español.

## Modelo de datos y listas de precios

- El esquema está en `supabase-schema.sql` (se ejecuta a mano en el SQL editor de Supabase). Ver "Autenticación y RLS" más abajo.
- Los clientes tienen `lista_precio` (`minorista` | `mayorista` | `distribuidor`); los productos tienen `precio_minorista` / `precio_mayorista` / `precio_distribuidor`, con `precio_venta` como respaldo. `ventas.js` elige el precio según la lista del cliente; `precios.js` los edita en línea (guarda al perder foco o con Enter).
- Las ventas se registran con la función `registrar_venta(cliente_id, items)` (RPC, SECURITY INVOKER): en una transacción crea la venta, sus detalles y suma el total al `saldo`; los precios los calcula el servidor según la lista del cliente y rechaza productos inactivos. `ventas.js` solo la invoca. Los movimientos manuales de saldo (compra a cuenta / pago) usan `registrar_movimiento_cliente(cliente_id, tipo, monto, concepto)`, y tanto las ventas como esos movimientos quedan en el historial `movimientos_cliente` (el saldo de `clientes` es la suma de sus movimientos). Cualquier cambio de saldo debe pasar por una de estas dos funciones, no por un `update` directo desde el navegador.

## Esquema y seguridad (estado actual)

`supabase-schema.sql` es el esquema completo de la base actual (proyecto Supabase `jklsoynymbpwvlaqwzhy`, cuenta nueva, región sa-east-1; aplicado el 2026-09-23 como migración `schema_inicial`), no un script incremental. Los tres archivos de `supabase/migrations/` fechados 20260923 son del proyecto original ya migrado: referencia histórica, no se vuelven a aplicar. Si se cambian tablas en Supabase, actualizar ese archivo. La base real es la fuente de verdad.

`productos.precio_venta` es NOT NULL (el formulario de precios lo exige).

## Deploy y keep-alive

El sitio se publica con GitHub Pages desde la rama `main` (raíz): https://fmz-mza.github.io/yogurlac/ ; cada push a `main` lo actualiza. El plan gratuito de Supabase pausa el proyecto tras ~1 semana sin actividad, por eso `.github/workflows/keep-alive.yml` llama una vez por día a la función `public.ping()` (lee URL y anon key de `js/supabase.js`). GitHub desactiva los crons tras ~60 días sin actividad en el repo: si pasa, reactivarlo en la pestaña Actions. El plan gratuito no incluye respaldos, por eso `.github/workflows/backup.yml` hace un `pg_dump` diario del esquema `public`, lo **cifra** (el repo es público y los artifacts de repos públicos son descargables por cualquiera) y lo sube como artifact por 90 días. Necesita los secrets del repo `SUPABASE_DB_URL` (cadena "Session pooler", porque la conexión directa es solo IPv6) y `BACKUP_PASSPHRASE`; las instrucciones para descargar, descifrar y restaurar están en los comentarios del workflow. Nunca commitear un volcado sin cifrar.

## Autenticación y RLS

La app la usan solo 2 dueños. Login con Supabase Auth (email + contraseña, registro público desactivado en el panel). `js/auth.js` se carga en todas las páginas, las oculta hasta verificar sesión y redirige a `login.html`; toda página nueva debe incluir `<style id="auth-oculto">body{visibility:hidden}</style>` en el `<head>` y `js/auth.js` justo después de `js/supabase.js`. Eso solo protege la interfaz: los datos los protege RLS, con la política `"Solo duenos"` (`es_dueno()`, que consulta la tabla `duenos`) en todas las tablas. Un usuario nuevo de Auth no ve nada hasta agregarlo a `duenos`. Los cambios de base van como migraciones en `supabase/migrations/` (nombradas con la versión que asigna Supabase al aplicarlas).

## Supabase MCP (herramientas para Claude)

`.mcp.json` define el servidor `supabase-yogurlac`, limitado al proyecto `jklsoynymbpwvlaqwzhy` con `project_ref` en la URL y autenticado con un token personal (PAT) de la cuenta de Supabase de YogurLac. El token vive en la variable de entorno de Windows `YOGURLAC_SUPABASE_PAT` (nunca en el repo ni en el chat); si falta, hay que regenerarlo en Supabase → Account → Access Tokens. Las herramientas son `mcp__supabase-yogurlac__*` y no llevan `project_id`. Existe además un conector de Claude ligado a *otra* cuenta de Supabase (otros proyectos): no usarlo para YogurLac y confirmar siempre el proyecto antes de aplicar cambios. Tras cambiar el token o el `.mcp.json` hay que reiniciar la app.
