-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260925115040).
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
