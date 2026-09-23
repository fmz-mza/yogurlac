-- APLICADA en Supabase el 2026-09-23 (version 20260923193036).
-- Registra una venta completa (cabecera + detalles + saldo del cliente) en una sola transacción.
-- SECURITY INVOKER: corre con los permisos del usuario, así que RLS (solo dueños) sigue aplicando.
-- Los precios los calcula el servidor según la lista del cliente; no se confía en los del navegador.
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

    -- Todos los productos deben existir, estar activos y tener cantidad > 0
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

    return v_venta_id;
end;
$$;

revoke execute on function public.registrar_venta(uuid, jsonb) from public, anon;
grant execute on function public.registrar_venta(uuid, jsonb) to authenticated;
