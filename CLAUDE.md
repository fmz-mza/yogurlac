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
- **Proveedores** (`proveedores.html` / `proveedores.js`) es la cuenta corriente con proveedores, espejo de Clientes: `proveedores.saldo` es lo que se le debe al proveedor (positivo = deuda propia). Las compras a cuenta lo suben y los pagos lo bajan mediante `registrar_movimiento_proveedor(proveedor_id, tipo, monto, concepto)`, que también guarda cada movimiento en `movimientos_proveedor` (historial visible con el botón Historial). El formulario de proveedores nunca toca `saldo`. Las tablas `ventas_diarias` y `cuenta_corriente` son de un diseño anterior, están vacías y ninguna pantalla las usa (se pueden eliminar).

## Flujo del negocio (léelo antes de tocar ventas, compras o pedidos)

El usuario hace un reparto de lácteos: compra a **Yogurlac** (el proveedor, con cuenta corriente y remitos en papel) y revende el mismo día. El flujo diario es **pedido → compra a Yogurlac (remito) → entrega y cobro**, y la idea central es que los datos se cargan **una sola vez** (el pedido) y el resto se deriva de ahí. Ganancia = venta − costo real pagado a Yogurlac; por eso `venta_detalles.costo_unitario` guarda el costo del momento (`costo_del_dia()`) y el dashboard usa ese costo, nunca `productos.costo` actual. Las cantidades (`pedido_items`, `compra_items`, `venta_detalles`) son `numeric(10,3)`: admiten hasta 3 decimales (productos por kilo); en el front usar `parseFloat`, `redondearCantidad()` y `formatCantidad()` de `js/utils.js`. Estado: implementados el costo histórico, **Pedidos** (`pedidos`, `pedido_items`, RPC `crear_pedido` / `actualizar_pedido` / `cancelar_pedido`, pantalla `pedidos.html` con el resumen "a comprar en Yogurlac") y **Compras** (`compras`, `compra_items`, RPC `registrar_compra` / `anular_compra`, pantalla `compras.html`: remito precargado con la suma de pedidos pendientes del día, se corrige lo realmente recibido y el costo; sube el saldo con el proveedor, opcionalmente actualiza `productos.costo`, y `costo_del_dia()` pasa a ser el promedio ponderado de las compras activas de ese día). Una compra mal cargada se **anula** (crédito automático), no se borra. `movimientos_proveedor.tipo` admite `compra` (suma), `pago` y `credito` (restan; devoluciones y anulaciones); el saldo inicial con Yogurlac se carga como una `compra` manual desde Proveedores, poniendo la fecha a la que corresponde el saldo (el formulario tiene campo Fecha; `registrar_movimiento_proveedor` acepta `p_fecha`). La pantalla Proveedores muestra el estado de cuenta por día vía `resumen_cuenta_proveedores(fecha)`: debías al cierre del día anterior, compras y pagos/créditos del día, saldo al día. Siguen: entrega y cobro por pedido (cantidades y precio editables por línea; pagó / a cuenta / parcial), cierre del día (comprado vs entregado, sobrante devuelto como crédito) y reportes por período.

## Esquema y seguridad (estado actual)

`supabase-schema.sql` es el esquema completo de la base actual (proyecto Supabase `jklsoynymbpwvlaqwzhy`, cuenta nueva, región sa-east-1; aplicado el 2026-09-23 como migración `schema_inicial`), no un script incremental. Los tres archivos de `supabase/migrations/` fechados 20260923 son del proyecto original ya migrado: referencia histórica, no se vuelven a aplicar. Si se cambian tablas en Supabase, actualizar ese archivo. La base real es la fuente de verdad.

`productos.precio_venta` es NOT NULL (el formulario de precios lo exige).

## Deploy y keep-alive

El sitio se publica con GitHub Pages desde la rama `main` (raíz): https://fmz-mza.github.io/yogurlac/ ; cada push a `main` lo actualiza. El plan gratuito de Supabase pausa el proyecto tras ~1 semana sin actividad, por eso `.github/workflows/keep-alive.yml` llama una vez por día a la función `public.ping()` (lee URL y anon key de `js/supabase.js`). GitHub desactiva los crons tras ~60 días sin actividad en el repo: si pasa, reactivarlo en la pestaña Actions. El plan gratuito no incluye respaldos, por eso `.github/workflows/backup.yml` hace un `pg_dump` diario del esquema `public`, lo **cifra** (el repo es público y los artifacts de repos públicos son descargables por cualquiera) y lo sube como artifact por 90 días. Necesita los secrets del repo `SUPABASE_DB_URL` (cadena "Session pooler", porque la conexión directa es solo IPv6) y `BACKUP_PASSPHRASE`; las instrucciones para descargar, descifrar y restaurar están en los comentarios del workflow. Nunca commitear un volcado sin cifrar.

## Autenticación y RLS

La app la usan solo 2 dueños. Login con Supabase Auth (email + contraseña, registro público desactivado en el panel). `js/auth.js` se carga en todas las páginas, las oculta hasta verificar sesión y redirige a `login.html`; toda página nueva debe incluir `<style id="auth-oculto">body{visibility:hidden}</style>` en el `<head>` y `js/auth.js` justo después de `js/supabase.js`. Eso solo protege la interfaz: los datos los protege RLS, con la política `"Solo duenos"` (`es_dueno()`, que consulta la tabla `duenos`) en todas las tablas. Un usuario nuevo de Auth no ve nada hasta agregarlo a `duenos`. Los cambios de base van como migraciones en `supabase/migrations/` (nombradas con la versión que asigna Supabase al aplicarlas).

## Supabase MCP (herramientas para Claude)

`.mcp.json` define el servidor `supabase-yogurlac`, limitado al proyecto `jklsoynymbpwvlaqwzhy` con `project_ref` en la URL y autenticado con un token personal (PAT) de la cuenta de Supabase de YogurLac. El token vive en la variable de entorno de Windows `YOGURLAC_SUPABASE_PAT` (nunca en el repo ni en el chat); si falta, hay que regenerarlo en Supabase → Account → Access Tokens. Las herramientas son `mcp__supabase-yogurlac__*` y no llevan `project_id`. Existe además un conector de Claude ligado a *otra* cuenta de Supabase (otros proyectos): no usarlo para YogurLac y confirmar siempre el proyecto antes de aplicar cambios. Tras cambiar el token o el `.mcp.json` hay que reiniciar la app.
