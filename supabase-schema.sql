-- Esquema de YogurLac (snapshot de la base real de Supabase, proyecto kqwnqhayodtjhdksdmfr).
-- Actualizado el 2026-09-23 leyendo la base directamente.
-- Es una foto del estado actual, NO un script incremental: para crear una base nueva
-- ejecutarlo completo; para cambiar la base existente usar migraciones.
--
-- ATENCIÓN: las políticas RLS de abajo son de desarrollo (acceso total a cualquiera con
-- la anon key) y ventas / venta_detalles ni siquiera tienen RLS. Reemplazar por
-- autenticación + políticas reales antes de producción.

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
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE TRIGGER set_updated_at_ventas BEFORE UPDATE ON ventas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Hoy el código NO la usa (el saldo se actualiza desde el navegador). Es SECURITY DEFINER
-- y ejecutable por el rol anon: cualquiera puede cambiar saldos. Pendiente de restringir.
CREATE OR REPLACE FUNCTION actualizar_saldo_cliente(p_cliente_id uuid, p_monto numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE clientes SET saldo = saldo + p_monto WHERE id = p_cliente_id;
END;
$$;

-- Índices
CREATE INDEX idx_ventas_fecha ON ventas(fecha DESC);
CREATE INDEX idx_ventas_cliente ON ventas(cliente_id);
CREATE INDEX idx_ventas_diarias_fecha ON ventas_diarias(fecha);
CREATE INDEX idx_cuenta_corriente_fecha ON cuenta_corriente(fecha);

-- RLS: habilitado en estas tablas, con política de desarrollo (acceso total)
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE proveedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas_diarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE cuenta_corriente ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all access" ON clientes FOR ALL USING (true);
CREATE POLICY "Allow all access" ON productos FOR ALL USING (true);
CREATE POLICY "Allow all access" ON proveedores FOR ALL USING (true);
CREATE POLICY "Allow all access" ON ventas_diarias FOR ALL USING (true);
CREATE POLICY "Allow all access" ON cuenta_corriente FOR ALL USING (true);

-- ventas y venta_detalles: SIN RLS en la base actual (expuestas por completo).
