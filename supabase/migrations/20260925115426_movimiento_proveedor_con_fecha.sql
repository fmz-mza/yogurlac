-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260925115426).
-- Los movimientos manuales con el proveedor (saldo inicial, pagos, créditos) admiten una fecha propia.
-- p_fecha nula = hoy (hora de Mendoza). Se reemplaza la función anterior de 4 parámetros.
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
