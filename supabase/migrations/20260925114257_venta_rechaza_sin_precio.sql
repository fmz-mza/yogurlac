-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260925114257).
-- registrar_venta rechaza productos sin precio de venta (null o <= 0) para la lista del cliente.
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
