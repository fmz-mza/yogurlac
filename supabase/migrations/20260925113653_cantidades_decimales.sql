-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260925113653).
-- Cantidades con hasta 3 decimales (productos por kilo: se puede vender 0,5 kg). Las tablas estaban vacías.

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
