-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260925180400).
-- Entrega de un pedido: crea la venta con las cantidades y precios REALMENTE entregados, registra el cobro
-- (pagó todo / parcial / a cuenta) y marca el pedido como entregado, todo en una transacción.
-- p_items: [{producto_id, cantidad, precio_unitario}]. p_monto_pagado: lo cobrado al entregar (0 = a cuenta).
-- El saldo del cliente sube por lo que NO pagó. SECURITY INVOKER: RLS (solo dueños) sigue aplicando.
create or replace function public.entregar_pedido(
    p_pedido_id uuid, p_items jsonb, p_monto_pagado numeric default 0)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_cliente uuid;
    v_estado text;
    v_venta_id uuid;
    v_total numeric(10,2);
    v_pagado numeric(10,2) := round(coalesce(p_monto_pagado, 0), 2);
    v_fecha date := (now() at time zone 'America/Argentina/Mendoza')::date;
begin
    select cliente_id, estado into v_cliente, v_estado
    from public.pedidos where id = p_pedido_id for update;
    if not found then
        raise exception 'Pedido no encontrado';
    end if;
    if v_estado <> 'pendiente' then
        raise exception 'Solo se pueden entregar pedidos pendientes';
    end if;

    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La entrega no tiene productos';
    end if;
    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric, precio_unitario numeric)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
              or i.precio_unitario is null or i.precio_unitario <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos, o con cantidad o precio inválido';
    end if;
    if (select count(*) - count(distinct producto_id)
        from jsonb_to_recordset(p_items) as i(producto_id uuid)) > 0 then
        raise exception 'Hay productos repetidos en la entrega';
    end if;

    insert into public.ventas (cliente_id, total, estado, fecha)
    values (v_cliente, 0, 'pendiente', v_fecha)
    returning id into v_venta_id;

    insert into public.venta_detalles (venta_id, producto_id, cantidad, precio_unitario, costo_unitario)
    select v_venta_id, i.producto_id, i.cantidad, i.precio_unitario,
           public.costo_del_dia(i.producto_id, v_fecha)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad numeric, precio_unitario numeric);

    select sum(subtotal) into v_total from public.venta_detalles where venta_id = v_venta_id;

    if v_pagado < 0 or v_pagado > v_total then
        raise exception 'El pago (%) no puede ser negativo ni superar el total (%)', v_pagado, v_total;
    end if;

    update public.ventas
    set total = v_total,
        estado = case when v_pagado >= v_total then 'pagada' else 'pendiente' end
    where id = v_venta_id;

    -- El cliente queda debiendo solo lo que no pagó
    update public.clientes set saldo = coalesce(saldo, 0) + v_total - v_pagado where id = v_cliente;
    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
    values (v_cliente, 'venta', v_total, 'Entrega de pedido', v_venta_id);
    if v_pagado > 0 then
        insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
        values (v_cliente, 'pago', v_pagado, 'Pago al entregar', v_venta_id);
    end if;

    update public.pedidos set estado = 'entregado', venta_id = v_venta_id where id = p_pedido_id;

    return v_venta_id;
end;
$$;
revoke execute on function public.entregar_pedido(uuid, jsonb, numeric) from public, anon;
grant execute on function public.entregar_pedido(uuid, jsonb, numeric) to authenticated;
