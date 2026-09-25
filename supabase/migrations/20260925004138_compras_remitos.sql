-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260925004138).
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
