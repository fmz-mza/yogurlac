-- Esquema de YogurLac (snapshot de la base real de Supabase, proyecto kqwnqhayodtjhdksdmfr).
-- Actualizado el 2026-09-23 leyendo la base directamente.
-- Es una foto del estado actual, NO un script incremental: para crear una base nueva
-- ejecutarlo completo; para cambiar la base existente usar migraciones.
--
-- Acceso: solo los dueños (tabla duenos + es_dueno()) vía RLS. Los usuarios se crean en
-- Supabase Auth con el registro público desactivado. Ver supabase/migrations/.

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

-- Sin uso en el código hoy (el saldo se actualiza desde el navegador). Ejecución revocada
-- para anon/authenticated; solo la puede llamar el service role.
CREATE OR REPLACE FUNCTION actualizar_saldo_cliente(p_cliente_id uuid, p_monto numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    UPDATE clientes SET saldo = saldo + p_monto WHERE id = p_cliente_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION actualizar_saldo_cliente(uuid, numeric) FROM PUBLIC, anon, authenticated;

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

-- Registra una venta completa: cabecera + detalles + saldo en una transacción (ver migración registrar_venta_rpc).
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
