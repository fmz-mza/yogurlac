-- Tabla: Clientes
CREATE TABLE clientes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    telefono VARCHAR(50),
    direccion TEXT,
    lista_precio VARCHAR(50),
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
    precio_venta DECIMAL(10, 2) NOT NULL,
    stock INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
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

-- Tabla: Ventas (Dashboard principal)
CREATE TABLE ventas (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    fecha DATE NOT NULL,
    cliente_id UUID REFERENCES clientes(id),
    producto_id UUID REFERENCES productos(id),
    cantidad INTEGER NOT NULL,
    total DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
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

-- Índices para mejor rendimiento
CREATE INDEX idx_ventas_fecha ON ventas(fecha);
CREATE INDEX idx_ventas_cliente ON ventas(cliente_id);
CREATE INDEX idx_ventas_diarias_fecha ON ventas_diarias(fecha);
CREATE INDEX idx_cuenta_corriente_fecha ON cuenta_corriente(fecha);

-- Políticas RLS (Row Level Security)
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE proveedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas_diarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE cuenta_corriente ENABLE ROW LEVEL SECURITY;

-- Políticas de acceso (para desarrollo - ajustar para producción)
CREATE POLICY "Allow all access" ON clientes FOR ALL USING (true);
CREATE POLICY "Allow all access" ON productos FOR ALL USING (true);
CREATE POLICY "Allow all access" ON proveedores FOR ALL USING (true);
CREATE POLICY "Allow all access" ON ventas FOR ALL USING (true);
CREATE POLICY "Allow all access" ON ventas_diarias FOR ALL USING (true);
CREATE POLICY "Allow all access" ON cuenta_corriente FOR ALL USING (true);
