-- Esquema completo de YogurLac. Ejecutarlo entero en el SQL editor de un proyecto Supabase NUEVO
-- (base vacía). Aplicado el 2026-09-23 en el proyecto actual (jklsoynymbpwvlaqwzhy) como
-- migración "schema_inicial". Los archivos de supabase/migrations/ anteriores a esa fecha son del
-- proyecto original (migrado a este) y quedan solo como referencia histórica.
--
-- Acceso: solo los dueños (tabla duenos + es_dueno()) vía RLS. Los usuarios se crean en
-- Supabase Auth con el registro público desactivado. Después de crear los usuarios, cargarlos:
--   insert into public.duenos (user_id) select id from auth.users where email in (...);

-- Tabla: Clientes
CREATE TABLE clientes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    telefono VARCHAR(50),
    direccion TEXT,
    lista_precio VARCHAR(50),               -- 'minorista' | 'mayorista' | 'distribuidor'
    saldo DECIMAL(10, 2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla: Productos
CREATE TABLE productos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    categoria VARCHAR(100),
    costo DECIMAL(10, 2) NOT NULL,
    precio_venta DECIMAL(10, 2) NOT NULL,   -- precio base, respaldo si falta el de la lista
    stock INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    precio_minorista DECIMAL(10, 2),
    precio_mayorista DECIMAL(10, 2),
    precio_distribuidor DECIMAL(10, 2),
    activo BOOLEAN DEFAULT TRUE
);

-- Tabla: Proveedores
CREATE TABLE proveedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    contacto VARCHAR(255),
    telefono VARCHAR(50),
    email VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla: Ventas (cabecera)
CREATE TABLE ventas (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    cliente_id UUID REFERENCES clientes(id),
    total DECIMAL(10, 2) NOT NULL DEFAULT 0,
    observaciones TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    estado VARCHAR(50) DEFAULT 'pendiente'
);

-- Tabla: Detalle de ventas (una fila por producto vendido)
CREATE TABLE venta_detalles (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    venta_id UUID REFERENCES ventas(id),
    producto_id UUID REFERENCES productos(id),
    cantidad INTEGER NOT NULL,
    precio_unitario DECIMAL(10, 2) NOT NULL,
    subtotal DECIMAL(10, 2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED
);

-- Tabla: Ventas Diarias (Proveedores)
CREATE TABLE ventas_diarias (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    fecha DATE NOT NULL,
    proveedor_id UUID REFERENCES proveedores(id),
    producto_id UUID REFERENCES productos(id),
    cantidad INTEGER NOT NULL,
    costo_unitario DECIMAL(10, 2) NOT NULL,
    precio_venta DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla: Cuenta Corriente
CREATE TABLE cuenta_corriente (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    fecha DATE NOT NULL,
    proveedor_id UUID REFERENCES proveedores(id),
    concepto VARCHAR(255) NOT NULL,
    debe DECIMAL(10, 2) DEFAULT 0,
    haber DECIMAL(10, 2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Funciones y triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE TRIGGER set_updated_at_ventas BEFORE UPDATE ON ventas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Índices
CREATE INDEX idx_ventas_fecha ON ventas(fecha DESC);
CREATE INDEX idx_ventas_cliente ON ventas(cliente_id);
CREATE INDEX idx_ventas_diarias_fecha ON ventas_diarias(fecha);
CREATE INDEX idx_cuenta_corriente_fecha ON cuenta_corriente(fecha);

-- Lista blanca de dueños (ids de auth.users). Sin políticas: la API no la puede leer.
CREATE TABLE duenos (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE duenos ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION es_dueno()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (SELECT 1 FROM public.duenos WHERE user_id = (SELECT auth.uid()));
$$;
REVOKE EXECUTE ON FUNCTION es_dueno() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION es_dueno() TO authenticated;

-- RLS en todas las tablas: solo dueños
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE proveedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE venta_detalles ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas_diarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE cuenta_corriente ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Solo duenos" ON clientes FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());
CREATE POLICY "Solo duenos" ON productos FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());
CREATE POLICY "Solo duenos" ON proveedores FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());
CREATE POLICY "Solo duenos" ON ventas FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());
CREATE POLICY "Solo duenos" ON venta_detalles FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());
CREATE POLICY "Solo duenos" ON ventas_diarias FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());
CREATE POLICY "Solo duenos" ON cuenta_corriente FOR ALL TO authenticated USING (es_dueno()) WITH CHECK (es_dueno());

-- Ventas y movimientos de cuenta corriente (ver migraciones registrar_venta_rpc y movimientos_cliente).
-- Historial de la cuenta corriente de cada cliente (ventas, compras a cuenta y pagos).
create table public.movimientos_cliente (
    id uuid primary key default gen_random_uuid(),
    cliente_id uuid not null references public.clientes(id),
    fecha date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    tipo varchar(20) not null check (tipo in ('venta', 'compra', 'pago')),
    monto numeric(10,2) not null check (monto > 0),   -- siempre positivo; el tipo define si suma (venta/compra) o resta (pago)
    concepto text,
    venta_id uuid references public.ventas(id) on delete set null,
    created_at timestamptz default now()
);
create index idx_movimientos_cliente on public.movimientos_cliente(cliente_id, fecha desc);

alter table public.movimientos_cliente enable row level security;
create policy "Solo duenos" on public.movimientos_cliente
    for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- Registra una compra a cuenta (suma deuda) o un pago (resta deuda): movimiento + saldo en una transacción.
-- Devuelve el saldo nuevo. SECURITY INVOKER: RLS (solo dueños) sigue aplicando.
create or replace function public.registrar_movimiento_cliente(
    p_cliente_id uuid, p_tipo text, p_monto numeric, p_concepto text default null)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_saldo numeric;
begin
    if p_tipo not in ('compra', 'pago') then
        raise exception 'Tipo de movimiento inválido';
    end if;
    if p_monto is null or p_monto <= 0 then
        raise exception 'El monto debe ser mayor a 0';
    end if;

    update public.clientes
    set saldo = coalesce(saldo, 0) + case p_tipo when 'compra' then p_monto else -p_monto end
    where id = p_cliente_id
    returning saldo into v_saldo;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto)
    values (p_cliente_id, p_tipo, p_monto, nullif(trim(p_concepto), ''));

    return v_saldo;
end;
$$;
revoke execute on function public.registrar_movimiento_cliente(uuid, text, numeric, text) from public, anon;
grant execute on function public.registrar_movimiento_cliente(uuid, text, numeric, text) to authenticated;

-- registrar_venta ahora también deja su movimiento en el historial
create or replace function public.registrar_venta(p_cliente_id uuid, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_lista text;
    v_venta_id uuid;
    v_total numeric(10,2);
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La venta no tiene productos';
    end if;

    select coalesce(lista_precio, 'minorista') into v_lista
    from public.clientes where id = p_cliente_id;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;

    insert into public.ventas (cliente_id, total, estado, fecha)
    values (p_cliente_id, 0, 'pendiente', (now() at time zone 'America/Argentina/Mendoza')::date)
    returning id into v_venta_id;

    insert into public.venta_detalles (venta_id, producto_id, cantidad, precio_unitario)
    select v_venta_id, p.id, i.cantidad,
           coalesce(
               case v_lista
                   when 'mayorista' then p.precio_mayorista
                   when 'distribuidor' then p.precio_distribuidor
                   else p.precio_minorista
               end,
               p.precio_venta)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    join public.productos p on p.id = i.producto_id;

    select sum(subtotal) into v_total from public.venta_detalles where venta_id = v_venta_id;

    update public.ventas set total = v_total where id = v_venta_id;
    update public.clientes set saldo = coalesce(saldo, 0) + v_total where id = p_cliente_id;
    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
    values (p_cliente_id, 'venta', v_total, 'Venta', v_venta_id);

    return v_venta_id;
end;
$$;
revoke execute on function public.registrar_venta(uuid, jsonb) from public, anon;
grant execute on function public.registrar_venta(uuid, jsonb) to authenticated;

-- Función mínima para el keep-alive diario (.github/workflows/keep-alive.yml). No expone datos.
create or replace function public.ping()
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
    select now();
$$;
grant execute on function public.ping() to anon, authenticated;

-- Cuenta corriente con proveedores (ver migración cuenta_corriente_proveedores). La columna
-- public.proveedores.saldo se agregó con esta migración (en un esquema desde cero iría en CREATE TABLE).
alter table public.proveedores add column saldo numeric(10,2) not null default 0;

create table public.movimientos_proveedor (
    id uuid primary key default gen_random_uuid(),
    proveedor_id uuid not null references public.proveedores(id),
    fecha date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    tipo varchar(20) not null check (tipo in ('compra', 'pago')),
    monto numeric(10,2) not null check (monto > 0),   -- siempre positivo; compra suma deuda, pago la resta
    concepto text,
    created_at timestamptz default now()
);
create index idx_movimientos_proveedor on public.movimientos_proveedor(proveedor_id, fecha desc);

alter table public.movimientos_proveedor enable row level security;
create policy "Solo duenos" on public.movimientos_proveedor
    for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- Registra una compra a cuenta (suma lo que se le debe) o un pago (lo resta): movimiento + saldo en una
-- transacción. Devuelve el saldo nuevo. SECURITY INVOKER: RLS (solo dueños) sigue aplicando.
create or replace function public.registrar_movimiento_proveedor(
    p_proveedor_id uuid, p_tipo text, p_monto numeric, p_concepto text default null)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_saldo numeric;
begin
    if p_tipo not in ('compra', 'pago') then
        raise exception 'Tipo de movimiento inválido';
    end if;
    if p_monto is null or p_monto <= 0 then
        raise exception 'El monto debe ser mayor a 0';
    end if;

    update public.proveedores
    set saldo = saldo + case p_tipo when 'compra' then p_monto else -p_monto end
    where id = p_proveedor_id
    returning saldo into v_saldo;
    if not found then
        raise exception 'Proveedor no encontrado';
    end if;

    insert into public.movimientos_proveedor (proveedor_id, tipo, monto, concepto)
    values (p_proveedor_id, p_tipo, p_monto, nullif(trim(p_concepto), ''));

    return v_saldo;
end;
$$;
revoke execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text) from public, anon;
grant execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text) to authenticated;

-- Costo histórico en las ventas (ver migración costo_historico_ventas). Redefine registrar_venta y costo_del_dia.
alter table public.venta_detalles add column costo_unitario numeric(10,2);

-- Filas anteriores: se completan con el costo actual (es lo mejor disponible)
update public.venta_detalles vd
set costo_unitario = p.costo
from public.productos p
where p.id = vd.producto_id and vd.costo_unitario is null;

alter table public.venta_detalles alter column costo_unitario set not null;

-- Costo de un producto para una fecha. Hoy: el costo vigente del producto.
-- (Más adelante se reemplaza para usar el costo real del remito de ese día.)
create or replace function public.costo_del_dia(p_producto_id uuid, p_fecha date)
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$
    select costo from public.productos where id = p_producto_id;
$$;
revoke execute on function public.costo_del_dia(uuid, date) from public, anon;
grant execute on function public.costo_del_dia(uuid, date) to authenticated;

-- registrar_venta ahora guarda el costo en cada línea
create or replace function public.registrar_venta(p_cliente_id uuid, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_lista text;
    v_venta_id uuid;
    v_total numeric(10,2);
    v_fecha date := (now() at time zone 'America/Argentina/Mendoza')::date;
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La venta no tiene productos';
    end if;

    select coalesce(lista_precio, 'minorista') into v_lista
    from public.clientes where id = p_cliente_id;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;

    insert into public.ventas (cliente_id, total, estado, fecha)
    values (p_cliente_id, 0, 'pendiente', v_fecha)
    returning id into v_venta_id;

    insert into public.venta_detalles (venta_id, producto_id, cantidad, precio_unitario, costo_unitario)
    select v_venta_id, p.id, i.cantidad,
           coalesce(
               case v_lista
                   when 'mayorista' then p.precio_mayorista
                   when 'distribuidor' then p.precio_distribuidor
                   else p.precio_minorista
               end,
               p.precio_venta),
           public.costo_del_dia(p.id, v_fecha)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    join public.productos p on p.id = i.producto_id;

    select sum(subtotal) into v_total from public.venta_detalles where venta_id = v_venta_id;

    update public.ventas set total = v_total where id = v_venta_id;
    update public.clientes set saldo = coalesce(saldo, 0) + v_total where id = p_cliente_id;
    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
    values (p_cliente_id, 'venta', v_total, 'Venta', v_venta_id);

    return v_venta_id;
end;
$$;

-- Pedidos (ver migración pedidos).
create table public.pedidos (
    id uuid primary key default gen_random_uuid(),
    cliente_id uuid not null references public.clientes(id),
    fecha_entrega date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    estado varchar(20) not null default 'pendiente' check (estado in ('pendiente', 'entregado', 'cancelado')),
    observaciones text,
    venta_id uuid references public.ventas(id) on delete set null,   -- se completa al entregar
    created_at timestamptz default now()
);
create index idx_pedidos_fecha on public.pedidos(fecha_entrega, estado);
create index idx_pedidos_cliente on public.pedidos(cliente_id);

create table public.pedido_items (
    id uuid primary key default gen_random_uuid(),
    pedido_id uuid not null references public.pedidos(id) on delete cascade,
    producto_id uuid not null references public.productos(id),
    cantidad integer not null check (cantidad > 0),
    unique (pedido_id, producto_id)
);
create index idx_pedido_items_pedido on public.pedido_items(pedido_id);

alter table public.pedidos enable row level security;
alter table public.pedido_items enable row level security;
create policy "Solo duenos" on public.pedidos for all to authenticated using (public.es_dueno()) with check (public.es_dueno());
create policy "Solo duenos" on public.pedido_items for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- Valida la lista de items [{producto_id, cantidad}]: no vacía, productos activos, cantidades > 0
create or replace function public.validar_items_pedido(p_items jsonb)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'El pedido no tiene productos';
    end if;
    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;
end;
$$;

-- Crea un pedido con sus items en una transacción. Si un producto se repite, se suman las cantidades.
create or replace function public.crear_pedido(
    p_cliente_id uuid, p_fecha date, p_items jsonb, p_observaciones text default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not exists (select 1 from public.clientes where id = p_cliente_id) then
        raise exception 'Cliente no encontrado';
    end if;
    perform public.validar_items_pedido(p_items);

    insert into public.pedidos (cliente_id, fecha_entrega, observaciones)
    values (p_cliente_id,
            coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date),
            nullif(trim(p_observaciones), ''))
    returning id into v_id;

    insert into public.pedido_items (pedido_id, producto_id, cantidad)
    select v_id, i.producto_id, sum(i.cantidad)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    group by i.producto_id;

    return v_id;
end;
$$;

-- Modifica un pedido PENDIENTE (fecha, observaciones e items completos).
create or replace function public.actualizar_pedido(
    p_pedido_id uuid, p_fecha date, p_items jsonb, p_observaciones text default null)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_estado text;
begin
    select estado into v_estado from public.pedidos where id = p_pedido_id for update;
    if not found then
        raise exception 'Pedido no encontrado';
    end if;
    if v_estado <> 'pendiente' then
        raise exception 'Solo se pueden modificar pedidos pendientes';
    end if;
    perform public.validar_items_pedido(p_items);

    update public.pedidos
    set fecha_entrega = coalesce(p_fecha, fecha_entrega),
        observaciones = nullif(trim(p_observaciones), '')
    where id = p_pedido_id;

    delete from public.pedido_items where pedido_id = p_pedido_id;
    insert into public.pedido_items (pedido_id, producto_id, cantidad)
    select p_pedido_id, i.producto_id, sum(i.cantidad)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    group by i.producto_id;
end;
$$;

-- Cancela un pedido PENDIENTE.
create or replace function public.cancelar_pedido(p_pedido_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_estado text;
begin
    select estado into v_estado from public.pedidos where id = p_pedido_id for update;
    if not found then
        raise exception 'Pedido no encontrado';
    end if;
    if v_estado <> 'pendiente' then
        raise exception 'Solo se pueden cancelar pedidos pendientes';
    end if;
    update public.pedidos set estado = 'cancelado' where id = p_pedido_id;
end;
$$;

revoke execute on function public.validar_items_pedido(jsonb) from public, anon;
revoke execute on function public.crear_pedido(uuid, date, jsonb, text) from public, anon;
revoke execute on function public.actualizar_pedido(uuid, date, jsonb, text) from public, anon;
revoke execute on function public.cancelar_pedido(uuid) from public, anon;
grant execute on function public.validar_items_pedido(jsonb) to authenticated;
grant execute on function public.crear_pedido(uuid, date, jsonb, text) to authenticated;
grant execute on function public.actualizar_pedido(uuid, date, jsonb, text) to authenticated;
grant execute on function public.cancelar_pedido(uuid) to authenticated;

-- Compras a proveedores / remitos (ver migración compras_remitos). Redefine registrar_movimiento_proveedor y costo_del_dia.
-- Compras a proveedores (remitos): lo que realmente se recibió, con su costo. Sube el saldo con el proveedor.
create table public.compras (
    id uuid primary key default gen_random_uuid(),
    proveedor_id uuid not null references public.proveedores(id),
    fecha date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    total numeric(10,2) not null default 0,
    estado varchar(20) not null default 'activa' check (estado in ('activa', 'anulada')),
    observaciones text,
    created_at timestamptz default now()
);
create index idx_compras_fecha on public.compras(fecha, estado);

create table public.compra_items (
    id uuid primary key default gen_random_uuid(),
    compra_id uuid not null references public.compras(id) on delete cascade,
    producto_id uuid not null references public.productos(id),
    cantidad integer not null check (cantidad > 0),
    costo_unitario numeric(10,2) not null check (costo_unitario >= 0),
    subtotal numeric(10,2) generated always as (cantidad * costo_unitario) stored,
    unique (compra_id, producto_id)
);
create index idx_compra_items_producto on public.compra_items(producto_id);

alter table public.compras enable row level security;
alter table public.compra_items enable row level security;
create policy "Solo duenos" on public.compras for all to authenticated using (public.es_dueno()) with check (public.es_dueno());
create policy "Solo duenos" on public.compra_items for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- La cuenta con el proveedor: nuevo tipo 'credito' (devoluciones, anulaciones) y vínculo con la compra
alter table public.movimientos_proveedor add column compra_id uuid references public.compras(id) on delete set null;
alter table public.movimientos_proveedor drop constraint movimientos_proveedor_tipo_check;
alter table public.movimientos_proveedor add constraint movimientos_proveedor_tipo_check
    check (tipo in ('compra', 'pago', 'credito'));

-- compra / pago / crédito manuales. compra suma lo que se le debe; pago y crédito lo restan.
create or replace function public.registrar_movimiento_proveedor(
    p_proveedor_id uuid, p_tipo text, p_monto numeric, p_concepto text default null)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_saldo numeric;
begin
    if p_tipo not in ('compra', 'pago', 'credito') then
        raise exception 'Tipo de movimiento inválido';
    end if;
    if p_monto is null or p_monto <= 0 then
        raise exception 'El monto debe ser mayor a 0';
    end if;

    update public.proveedores
    set saldo = saldo + case p_tipo when 'compra' then p_monto else -p_monto end
    where id = p_proveedor_id
    returning saldo into v_saldo;
    if not found then
        raise exception 'Proveedor no encontrado';
    end if;

    insert into public.movimientos_proveedor (proveedor_id, tipo, monto, concepto)
    values (p_proveedor_id, p_tipo, p_monto, nullif(trim(p_concepto), ''));

    return v_saldo;
end;
$$;

-- Registra un remito: compra + líneas + saldo con el proveedor + movimiento, todo en una transacción.
-- p_items: [{producto_id, cantidad, costo_unitario}]. Si p_actualizar_costos, el costo del producto pasa a ser
-- el del remito (salvo que ya exista una compra activa más nueva de ese producto).
create or replace function public.registrar_compra(
    p_proveedor_id uuid, p_fecha date, p_items jsonb,
    p_actualizar_costos boolean default true, p_observaciones text default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_id uuid;
    v_fecha date := coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date);
    v_total numeric(10,2);
begin
    if not exists (select 1 from public.proveedores where id = p_proveedor_id) then
        raise exception 'Proveedor no encontrado';
    end if;
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La compra no tiene productos';
    end if;
    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int, costo_unitario numeric)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
              or i.costo_unitario is null or i.costo_unitario < 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos, con cantidad o costo inválido';
    end if;
    if (select count(*) - count(distinct producto_id)
        from jsonb_to_recordset(p_items) as i(producto_id uuid)) > 0 then
        raise exception 'Hay productos repetidos en el remito';
    end if;

    insert into public.compras (proveedor_id, fecha, observaciones)
    values (p_proveedor_id, v_fecha, nullif(trim(p_observaciones), ''))
    returning id into v_id;

    insert into public.compra_items (compra_id, producto_id, cantidad, costo_unitario)
    select v_id, i.producto_id, i.cantidad, i.costo_unitario
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int, costo_unitario numeric);

    select sum(subtotal) into v_total from public.compra_items where compra_id = v_id;
    if v_total is null or v_total <= 0 then
        raise exception 'El total del remito debe ser mayor a 0';
    end if;

    update public.compras set total = v_total where id = v_id;
    update public.proveedores set saldo = saldo + v_total where id = p_proveedor_id;
    insert into public.movimientos_proveedor (proveedor_id, fecha, tipo, monto, concepto, compra_id)
    values (p_proveedor_id, v_fecha, 'compra', v_total, 'Remito', v_id);

    if p_actualizar_costos then
        update public.productos p
        set costo = ci.costo_unitario
        from public.compra_items ci
        where ci.compra_id = v_id
          and p.id = ci.producto_id
          and p.costo is distinct from ci.costo_unitario
          and not exists (
              select 1
              from public.compra_items ci2
              join public.compras c2 on c2.id = ci2.compra_id
              where ci2.producto_id = ci.producto_id and c2.estado = 'activa' and c2.fecha > v_fecha
          );
    end if;

    return v_id;
end;
$$;

-- Anula una compra ACTIVA: baja el saldo con un crédito y deja el registro (no se borra nada).
-- No revierte el costo actualizado de los productos ni el costo ya guardado en ventas.
create or replace function public.anular_compra(p_compra_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_prov uuid;
    v_total numeric(10,2);
    v_estado text;
    v_fecha date;
begin
    select proveedor_id, total, estado, fecha into v_prov, v_total, v_estado, v_fecha
    from public.compras where id = p_compra_id for update;
    if not found then
        raise exception 'Compra no encontrada';
    end if;
    if v_estado <> 'activa' then
        raise exception 'La compra ya está anulada';
    end if;

    update public.compras set estado = 'anulada' where id = p_compra_id;
    update public.proveedores set saldo = saldo - v_total where id = v_prov;
    insert into public.movimientos_proveedor (proveedor_id, tipo, monto, concepto, compra_id)
    values (v_prov, 'credito', v_total, 'Anulación de compra del ' || to_char(v_fecha, 'DD/MM/YYYY'), p_compra_id);
end;
$$;

-- Costo de un producto para una fecha: promedio ponderado de las compras ACTIVAS de ese día;
-- si no hubo compra ese día, el costo vigente del producto.
create or replace function public.costo_del_dia(p_producto_id uuid, p_fecha date)
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$
    select coalesce(
        (select sum(ci.cantidad * ci.costo_unitario) / sum(ci.cantidad)
         from public.compra_items ci
         join public.compras c on c.id = ci.compra_id
         where ci.producto_id = p_producto_id and c.fecha = p_fecha and c.estado = 'activa'),
        (select costo from public.productos where id = p_producto_id)
    );
$$;

revoke execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text) from public, anon;
revoke execute on function public.registrar_compra(uuid, date, jsonb, boolean, text) from public, anon;
revoke execute on function public.anular_compra(uuid) from public, anon;
revoke execute on function public.costo_del_dia(uuid, date) from public, anon;
grant execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text) to authenticated;
grant execute on function public.registrar_compra(uuid, date, jsonb, boolean, text) to authenticated;
grant execute on function public.anular_compra(uuid) to authenticated;
grant execute on function public.costo_del_dia(uuid, date) to authenticated;

-- Cantidades decimales (ver migración cantidades_decimales). Redefine las funciones con cantidad numeric.

-- pedido_items
alter table public.pedido_items alter column cantidad type numeric(10,3);

-- compra_items y venta_detalles tienen un subtotal generado que depende de cantidad: se recrea
alter table public.compra_items drop column subtotal;
alter table public.compra_items alter column cantidad type numeric(10,3);
alter table public.compra_items add column subtotal numeric(10,2) generated always as (cantidad * costo_unitario) stored;

alter table public.venta_detalles drop column subtotal;
alter table public.venta_detalles alter column cantidad type numeric(10,3);
alter table public.venta_detalles add column subtotal numeric(10,2) generated always as (cantidad * precio_unitario) stored;

-- Funciones: los items del JSON ahora traen cantidad numérica
create or replace function public.validar_items_pedido(p_items jsonb)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'El pedido no tiene productos';
    end if;
    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;
end;
$$;

create or replace function public.crear_pedido(
    p_cliente_id uuid, p_fecha date, p_items jsonb, p_observaciones text default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not exists (select 1 from public.clientes where id = p_cliente_id) then
        raise exception 'Cliente no encontrado';
    end if;
    perform public.validar_items_pedido(p_items);

    insert into public.pedidos (cliente_id, fecha_entrega, observaciones)
    values (p_cliente_id,
            coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date),
            nullif(trim(p_observaciones), ''))
    returning id into v_id;

    insert into public.pedido_items (pedido_id, producto_id, cantidad)
    select v_id, i.producto_id, sum(i.cantidad)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
    group by i.producto_id;

    return v_id;
end;
$$;

create or replace function public.actualizar_pedido(
    p_pedido_id uuid, p_fecha date, p_items jsonb, p_observaciones text default null)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_estado text;
begin
    select estado into v_estado from public.pedidos where id = p_pedido_id for update;
    if not found then
        raise exception 'Pedido no encontrado';
    end if;
    if v_estado <> 'pendiente' then
        raise exception 'Solo se pueden modificar pedidos pendientes';
    end if;
    perform public.validar_items_pedido(p_items);

    update public.pedidos
    set fecha_entrega = coalesce(p_fecha, fecha_entrega),
        observaciones = nullif(trim(p_observaciones), '')
    where id = p_pedido_id;

    delete from public.pedido_items where pedido_id = p_pedido_id;
    insert into public.pedido_items (pedido_id, producto_id, cantidad)
    select p_pedido_id, i.producto_id, sum(i.cantidad)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
    group by i.producto_id;
end;
$$;

create or replace function public.registrar_venta(p_cliente_id uuid, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_lista text;
    v_venta_id uuid;
    v_total numeric(10,2);
    v_fecha date := (now() at time zone 'America/Argentina/Mendoza')::date;
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La venta no tiene productos';
    end if;

    select coalesce(lista_precio, 'minorista') into v_lista
    from public.clientes where id = p_cliente_id;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;

    insert into public.ventas (cliente_id, total, estado, fecha)
    values (p_cliente_id, 0, 'pendiente', v_fecha)
    returning id into v_venta_id;

    insert into public.venta_detalles (venta_id, producto_id, cantidad, precio_unitario, costo_unitario)
    select v_venta_id, p.id, i.cantidad,
           coalesce(
               case v_lista
                   when 'mayorista' then p.precio_mayorista
                   when 'distribuidor' then p.precio_distribuidor
                   else p.precio_minorista
               end,
               p.precio_venta),
           public.costo_del_dia(p.id, v_fecha)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
    join public.productos p on p.id = i.producto_id;

    select sum(subtotal) into v_total from public.venta_detalles where venta_id = v_venta_id;

    update public.ventas set total = v_total where id = v_venta_id;
    update public.clientes set saldo = coalesce(saldo, 0) + v_total where id = p_cliente_id;
    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
    values (p_cliente_id, 'venta', v_total, 'Venta', v_venta_id);

    return v_venta_id;
end;
$$;

create or replace function public.registrar_compra(
    p_proveedor_id uuid, p_fecha date, p_items jsonb,
    p_actualizar_costos boolean default true, p_observaciones text default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_id uuid;
    v_fecha date := coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date);
    v_total numeric(10,2);
begin
    if not exists (select 1 from public.proveedores where id = p_proveedor_id) then
        raise exception 'Proveedor no encontrado';
    end if;
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La compra no tiene productos';
    end if;
    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric, costo_unitario numeric)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
              or i.costo_unitario is null or i.costo_unitario < 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos, con cantidad o costo inválido';
    end if;
    if (select count(*) - count(distinct producto_id)
        from jsonb_to_recordset(p_items) as i(producto_id uuid)) > 0 then
        raise exception 'Hay productos repetidos en el remito';
    end if;

    insert into public.compras (proveedor_id, fecha, observaciones)
    values (p_proveedor_id, v_fecha, nullif(trim(p_observaciones), ''))
    returning id into v_id;

    insert into public.compra_items (compra_id, producto_id, cantidad, costo_unitario)
    select v_id, i.producto_id, i.cantidad, i.costo_unitario
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric, costo_unitario numeric);

    select sum(subtotal) into v_total from public.compra_items where compra_id = v_id;
    if v_total is null or v_total <= 0 then
        raise exception 'El total del remito debe ser mayor a 0';
    end if;

    update public.compras set total = v_total where id = v_id;
    update public.proveedores set saldo = saldo + v_total where id = p_proveedor_id;
    insert into public.movimientos_proveedor (proveedor_id, fecha, tipo, monto, concepto, compra_id)
    values (p_proveedor_id, v_fecha, 'compra', v_total, 'Remito', v_id);

    if p_actualizar_costos then
        update public.productos p
        set costo = ci.costo_unitario
        from public.compra_items ci
        where ci.compra_id = v_id
          and p.id = ci.producto_id
          and p.costo is distinct from ci.costo_unitario
          and not exists (
              select 1
              from public.compra_items ci2
              join public.compras c2 on c2.id = ci2.compra_id
              where ci2.producto_id = ci.producto_id and c2.estado = 'activa' and c2.fecha > v_fecha
          );
    end if;

    return v_id;
end;
$$;

-- registrar_venta rechaza productos sin precio (ver migración venta_rechaza_sin_precio).
create or replace function public.registrar_venta(p_cliente_id uuid, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_lista text;
    v_venta_id uuid;
    v_total numeric(10,2);
    v_fecha date := (now() at time zone 'America/Argentina/Mendoza')::date;
    v_sin_precio text;
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La venta no tiene productos';
    end if;

    select coalesce(lista_precio, 'minorista') into v_lista
    from public.clientes where id = p_cliente_id;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;

    -- Nunca vender un producto sin precio para esta lista
    select string_agg(p.nombre, ', ') into v_sin_precio
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
    join public.productos p on p.id = i.producto_id
    where coalesce(
              case v_lista
                  when 'mayorista' then p.precio_mayorista
                  when 'distribuidor' then p.precio_distribuidor
                  else p.precio_minorista
              end,
              p.precio_venta) is null
       or coalesce(
              case v_lista
                  when 'mayorista' then p.precio_mayorista
                  when 'distribuidor' then p.precio_distribuidor
                  else p.precio_minorista
              end,
              p.precio_venta) <= 0;
    if v_sin_precio is not null then
        raise exception 'Sin precio de venta para la lista "%": %', v_lista, v_sin_precio;
    end if;

    insert into public.ventas (cliente_id, total, estado, fecha)
    values (p_cliente_id, 0, 'pendiente', v_fecha)
    returning id into v_venta_id;

    insert into public.venta_detalles (venta_id, producto_id, cantidad, precio_unitario, costo_unitario)
    select v_venta_id, p.id, i.cantidad,
           coalesce(
               case v_lista
                   when 'mayorista' then p.precio_mayorista
                   when 'distribuidor' then p.precio_distribuidor
                   else p.precio_minorista
               end,
               p.precio_venta),
           public.costo_del_dia(p.id, v_fecha)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric)
    join public.productos p on p.id = i.producto_id;

    select sum(subtotal) into v_total from public.venta_detalles where venta_id = v_venta_id;

    update public.ventas set total = v_total where id = v_venta_id;
    update public.clientes set saldo = coalesce(saldo, 0) + v_total where id = p_cliente_id;
    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
    values (p_cliente_id, 'venta', v_total, 'Venta', v_venta_id);

    return v_venta_id;
end;
$$;

-- Estado de cuenta por día de los proveedores (ver migración resumen_cuenta_proveedores).
-- Estado de cuenta por día de cada proveedor: lo que se debía al cierre del día anterior, los movimientos
-- del día (compras suman; pagos y créditos restan) y el saldo al cierre de ese día.
-- p_fecha nula = hoy (hora de Mendoza). SECURITY INVOKER: RLS (solo dueños) sigue aplicando.
create or replace function public.resumen_cuenta_proveedores(p_fecha date default null)
returns table (
    proveedor_id uuid,
    saldo_anterior numeric,
    compras numeric,
    pagos numeric,
    creditos numeric,
    saldo_al_dia numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
    with dia as (
        select coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date) as f
    )
    select
        p.id,
        coalesce(sum(case when m.fecha < d.f
                          then case m.tipo when 'compra' then m.monto else -m.monto end end), 0),
        coalesce(sum(case when m.fecha = d.f and m.tipo = 'compra'  then m.monto end), 0),
        coalesce(sum(case when m.fecha = d.f and m.tipo = 'pago'    then m.monto end), 0),
        coalesce(sum(case when m.fecha = d.f and m.tipo = 'credito' then m.monto end), 0),
        coalesce(sum(case when m.fecha <= d.f
                          then case m.tipo when 'compra' then m.monto else -m.monto end end), 0)
    from public.proveedores p
    cross join dia d
    left join public.movimientos_proveedor m on m.proveedor_id = p.id
    group by p.id, d.f;
$$;
revoke execute on function public.resumen_cuenta_proveedores(date) from public, anon;
grant execute on function public.resumen_cuenta_proveedores(date) to authenticated;

-- Movimientos manuales con proveedor con fecha propia (ver migración movimiento_proveedor_con_fecha).
drop function if exists public.registrar_movimiento_proveedor(uuid, text, numeric, text);

create or replace function public.registrar_movimiento_proveedor(
    p_proveedor_id uuid, p_tipo text, p_monto numeric, p_concepto text default null, p_fecha date default null)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_saldo numeric;
begin
    if p_tipo not in ('compra', 'pago', 'credito') then
        raise exception 'Tipo de movimiento inválido';
    end if;
    if p_monto is null or p_monto <= 0 then
        raise exception 'El monto debe ser mayor a 0';
    end if;

    update public.proveedores
    set saldo = saldo + case p_tipo when 'compra' then p_monto else -p_monto end
    where id = p_proveedor_id
    returning saldo into v_saldo;
    if not found then
        raise exception 'Proveedor no encontrado';
    end if;

    insert into public.movimientos_proveedor (proveedor_id, fecha, tipo, monto, concepto)
    values (p_proveedor_id,
            coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date),
            p_tipo, p_monto, nullif(trim(p_concepto), ''));

    return v_saldo;
end;
$$;
revoke execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text, date) from public, anon;
grant execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text, date) to authenticated;
