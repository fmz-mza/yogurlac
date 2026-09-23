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

- El esquema está en `supabase-schema.sql` (se ejecuta a mano en el SQL editor de Supabase). RLS está habilitado con políticas permisivas `USING (true)` "para desarrollo".
- Los clientes tienen `lista_precio` (`minorista` | `mayorista` | `distribuidor`); los productos tienen `precio_minorista` / `precio_mayorista` / `precio_distribuidor`, con `precio_venta` como respaldo. `ventas.js` elige el precio según la lista del cliente; `precios.js` los edita en línea (guarda al perder foco o con Enter).
- El `saldo` del cliente se actualiza con lectura y luego escritura desde el navegador (en `ventas.js` al vender, en `clientes.js` con pagos); no es atómico.

## Esquema y seguridad (estado actual)

`supabase-schema.sql` es una foto de la base real (proyecto Supabase `kqwnqhayodtjhdksdmfr`, leída el 2026-09-23), no un script incremental. Si se cambian tablas en Supabase, actualizar ese archivo. La base real es la fuente de verdad.

Pendientes de seguridad antes de producción: `ventas` y `venta_detalles` no tienen RLS; el resto tiene políticas `USING (true)`; y `actualizar_saldo_cliente` (SECURITY DEFINER, sin uso en el código) la puede ejecutar el rol `anon`. `productos.precio_venta` es NOT NULL (el formulario de precios lo exige).