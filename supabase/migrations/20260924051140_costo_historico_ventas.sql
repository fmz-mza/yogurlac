-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260924051140).
-- Cada línea de venta guarda el costo del momento, así la ganancia pasada no cambia cuando el proveedor sube precios.
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
