// Compras a Yogurlac (remito): se cargan las cantidades REALMENTE recibidas y su costo.
// Al registrar, el servidor sube el saldo con el proveedor, guarda el remito y (opcionalmente)
// actualiza el costo de los productos. El costo de las ventas del día sale de este remito.
let productosLista = [];   // productos activos [{id, nombre, costo}]
let proveedoresLista = []; // [{id, nombre}]
let lineas = [];           // renglones del remito [{producto_id, pedido, cantidad, costo}]
let pedidoPorProducto = new Map(); // producto_id -> cantidad total pedida (pendientes del día)
let comprasActivasDelDia = 0;
const comprasPorId = new Map();

// Fecha local (YYYY-MM-DD) sin pasar por UTC, para que de noche no salte al día siguiente
function fechaLocal(d = new Date()) {
    const mes = String(d.getMonth() + 1).padStart(2, '0');
    const dia = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${mes}-${dia}`;
}
function sumarDias(fechaISO, dias) {
    const [a, m, d] = fechaISO.split('-').map(Number);
    return fechaLocal(new Date(a, m - 1, d + dias));
}
function fechaLegible(fechaISO) {
    const [a, m, d] = fechaISO.split('-').map(Number);
    return new Date(a, m - 1, d).toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long' });
}
function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(amount || 0);
}

document.addEventListener('DOMContentLoaded', async () => {
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', () => mobileMenu.classList.toggle('hidden'));
    }

    const inputFecha = document.getElementById('fecha-compra');
    inputFecha.value = fechaLocal();
    inputFecha.addEventListener('change', cargarDia);
    document.getElementById('btn-hoy').addEventListener('click', () => { inputFecha.value = fechaLocal(); cargarDia(); });
    document.getElementById('btn-dia-anterior').addEventListener('click', () => { inputFecha.value = sumarDias(inputFecha.value, -1); cargarDia(); });
    document.getElementById('btn-dia-siguiente').addEventListener('click', () => { inputFecha.value = sumarDias(inputFecha.value, 1); cargarDia(); });
    document.getElementById('btn-agregar-linea').addEventListener('click', () => agregarLineaExtra());
    document.getElementById('btn-precargar').addEventListener('click', () => { precargarDesdePedidos(); renderRemito(); });
    document.getElementById('btn-registrar-compra').addEventListener('click', registrarCompra);

    await cargarCatalogos();
    await cargarDia();
});

async function cargarCatalogos() {
    const [{ data: productos, error: e1 }, { data: proveedores, error: e2 }] = await Promise.all([
        window.supabaseClient.from('productos').select('id, nombre, costo').eq('activo', true).order('nombre'),
        window.supabaseClient.from('proveedores').select('id, nombre').order('nombre')
    ]);
    if (e1 || e2) console.error('Error cargando catálogos:', e1 || e2);
    productosLista = productos || [];
    proveedoresLista = proveedores || [];

    const select = document.getElementById('compra-proveedor');
    select.innerHTML = '';
    proveedoresLista.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.nombre;
        select.appendChild(opt);
    });
    document.getElementById('aviso-sin-proveedor').classList.toggle('hidden', proveedoresLista.length > 0);
    document.getElementById('btn-registrar-compra').disabled = proveedoresLista.length === 0;
}

async function cargarDia() {
    const fecha = document.getElementById('fecha-compra').value;
    if (!fecha) return;
    document.getElementById('fecha-legible').textContent = fechaLegible(fecha);

    const [{ data: pedidos, error: e1 }, { data: compras, error: e2 }] = await Promise.all([
        window.supabaseClient
            .from('pedidos')
            .select('id, pedido_items(producto_id, cantidad)')
            .eq('fecha_entrega', fecha)
            .eq('estado', 'pendiente'),
        window.supabaseClient
            .from('compras')
            .select('id, fecha, total, estado, created_at, proveedores(nombre), compra_items(cantidad, costo_unitario, productos(nombre))')
            .eq('fecha', fecha)
            .order('created_at', { ascending: true })
    ]);
    if (e1 || e2) console.error('Error cargando el día:', e1 || e2);

    // Total pedido por producto (solo pedidos pendientes)
    pedidoPorProducto = new Map();
    (pedidos || []).forEach(p => (p.pedido_items || []).forEach(it => {
        pedidoPorProducto.set(it.producto_id, redondearCantidad((pedidoPorProducto.get(it.producto_id) || 0) + Number(it.cantidad)));
    }));

    comprasPorId.clear();
    (compras || []).forEach(c => comprasPorId.set(c.id, c));
    comprasActivasDelDia = (compras || []).filter(c => c.estado === 'activa').length;

    // Si ya hay una compra registrada ese día, no se precarga (evita cargar el mismo remito dos veces)
    lineas = [];
    const aviso = document.getElementById('aviso-compra-existente');
    if (comprasActivasDelDia > 0) {
        aviso.classList.remove('hidden');
        document.getElementById('aviso-compra-texto').textContent =
            `Ya registraste ${comprasActivasDelDia} compra${comprasActivasDelDia > 1 ? 's' : ''} este día. El remito está vacío para no duplicarla.`;
    } else {
        aviso.classList.add('hidden');
        precargarDesdePedidos();
    }

    renderRemito();
    renderCompras(compras || []);
}

// Una línea por producto pedido, con lo pedido como cantidad y el costo vigente
function precargarDesdePedidos() {
    lineas = [];
    [...pedidoPorProducto.entries()].forEach(([productoId, cantidad]) => {
        const prod = productosLista.find(p => p.id === productoId);
        if (!prod) return; // producto que ya no está activo
        lineas.push({ producto_id: productoId, pedido: cantidad, cantidad, costo: Number(prod.costo) || 0 });
    });
    lineas.sort((a, b) => nombreProducto(a.producto_id).localeCompare(nombreProducto(b.producto_id), 'es'));
}

function nombreProducto(id) {
    return productosLista.find(p => p.id === id)?.nombre || '(producto)';
}

function agregarLineaExtra() {
    const usados = new Set(lineas.map(l => l.producto_id));
    const libre = productosLista.find(p => !usados.has(p.id));
    if (!libre) { alert('Ya están todos los productos en el remito.'); return; }
    lineas.push({ producto_id: libre.id, pedido: pedidoPorProducto.get(libre.id) || 0, cantidad: 1, costo: Number(libre.costo) || 0 });
    renderRemito();
}

function renderRemito() {
    const tbody = document.getElementById('remito-body');
    tbody.innerHTML = '';

    if (lineas.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="px-4 py-8 text-center text-sm text-gray-500">No hay productos en el remito. Agregá los que te entregaron.</td></tr>';
        actualizarTotal();
        return;
    }

    lineas.forEach((l, idx) => {
        const tr = document.createElement('tr');

        // Producto (select para poder cambiarlo)
        const tdProd = document.createElement('td');
        tdProd.className = 'px-4 py-2 text-sm text-gray-900';
        const select = document.createElement('select');
        select.className = 'border border-gray-300 rounded-md px-2 py-1 bg-white max-w-[14rem]';
        productosLista.forEach(p => {
            const opt = document.createElement('option');
            opt.value = p.id;
            opt.textContent = p.nombre;
            select.appendChild(opt);
        });
        select.value = l.producto_id;
        select.addEventListener('change', () => {
            const nuevo = productosLista.find(p => p.id === select.value);
            l.producto_id = select.value;
            l.pedido = pedidoPorProducto.get(select.value) || 0;
            l.costo = Number(nuevo?.costo) || 0;
            renderRemito();
        });
        tdProd.appendChild(select);
        const aviso = document.createElement('div');
        aviso.className = 'text-xs text-amber-600 mt-1';
        tdProd.appendChild(aviso);

        // Pedido
        const tdPed = document.createElement('td');
        tdPed.className = 'px-4 py-2 text-sm text-right text-gray-600';
        tdPed.textContent = l.pedido > 0 ? formatCantidad(l.pedido) : '—';

        // Recibido
        const tdCant = document.createElement('td');
        tdCant.className = 'px-4 py-2';
        const inCant = document.createElement('input');
        inCant.type = 'number'; inCant.min = '0'; inCant.step = '0.001'; // admite decimales (productos por kilo)
        inCant.className = 'w-24 border border-gray-300 rounded-md px-2 py-1';
        inCant.value = l.cantidad;
        const dif = document.createElement('div');
        dif.className = 'text-xs mt-1';
        tdCant.append(inCant, dif);

        // Costo
        const tdCosto = document.createElement('td');
        tdCosto.className = 'px-4 py-2';
        const inCosto = document.createElement('input');
        inCosto.type = 'number'; inCosto.min = '0'; inCosto.step = '0.01';
        inCosto.className = 'w-28 border border-gray-300 rounded-md px-2 py-1';
        inCosto.value = l.costo;
        tdCosto.appendChild(inCosto);

        // Subtotal
        const tdSub = document.createElement('td');
        tdSub.className = 'px-4 py-2 text-sm text-right font-semibold text-gray-900';

        // Quitar
        const tdQuitar = document.createElement('td');
        tdQuitar.className = 'px-2 py-2 text-right';
        const quitar = document.createElement('button');
        quitar.type = 'button';
        quitar.textContent = '✕';
        quitar.setAttribute('aria-label', 'Quitar producto');
        quitar.className = 'text-red-500 hover:text-red-700 px-2';
        quitar.addEventListener('click', () => { lineas.splice(idx, 1); renderRemito(); });
        tdQuitar.appendChild(quitar);

        const refrescar = () => {
            l.cantidad = redondearCantidad(parseFloat(inCant.value) || 0);
            l.costo = parseFloat(inCosto.value) || 0;
            tdSub.textContent = formatCurrency(l.cantidad * l.costo);

            // Diferencia entre lo recibido y lo pedido
            const d = redondearCantidad(l.cantidad - l.pedido);
            if (l.pedido > 0 && d !== 0) {
                dif.textContent = d < 0 ? `Faltan ${formatCantidad(-d)}` : `Sobran ${formatCantidad(d)}`;
                dif.className = 'text-xs mt-1 ' + (d < 0 ? 'text-red-600' : 'text-blue-600');
            } else {
                dif.textContent = '';
            }
            // Cambio de precio respecto del costo actual del producto
            const prod = productosLista.find(p => p.id === l.producto_id);
            const actual = Number(prod?.costo) || 0;
            aviso.textContent = Math.abs(l.costo - actual) > 0.001
                ? `Antes ${formatCurrency(actual)} → ahora ${formatCurrency(l.costo)}` : '';
            actualizarTotal();
        };
        inCant.addEventListener('input', refrescar);
        inCosto.addEventListener('input', refrescar);

        tr.append(tdProd, tdPed, tdCant, tdCosto, tdSub, tdQuitar);
        tbody.appendChild(tr);
        refrescar();
    });
}

function actualizarTotal() {
    const total = lineas.reduce((s, l) => s + l.cantidad * l.costo, 0);
    document.getElementById('remito-total').textContent = formatCurrency(total);
}

async function registrarCompra() {
    const proveedorId = document.getElementById('compra-proveedor').value;
    const fecha = document.getElementById('fecha-compra').value;
    const items = lineas.filter(l => l.cantidad > 0).map(l => ({
        producto_id: l.producto_id, cantidad: l.cantidad, costo_unitario: l.costo
    }));

    if (!proveedorId) { alert('Elegí un proveedor.'); return; }
    if (items.length === 0) { alert('El remito no tiene productos con cantidad.'); return; }
    if (new Set(items.map(i => i.producto_id)).size !== items.length) {
        alert('Hay un producto repetido en el remito. Dejá una sola línea por producto.');
        return;
    }
    const total = items.reduce((s, i) => s + i.cantidad * i.costo_unitario, 0);
    if (!confirm(`Registrar compra por ${formatCurrency(total)}?\nSube tu saldo con ${document.getElementById('compra-proveedor').selectedOptions[0].textContent}.`)) return;

    const btn = document.getElementById('btn-registrar-compra');
    const textoOriginal = btn.textContent;
    btn.textContent = 'Registrando...';
    btn.disabled = true;
    try {
        const { error } = await window.supabaseClient.rpc('registrar_compra', {
            p_proveedor_id: proveedorId,
            p_fecha: fecha,
            p_items: items,
            p_actualizar_costos: document.getElementById('chk-actualizar-costos').checked,
            p_observaciones: null
        });
        if (error) throw error;

        alert('✅ Compra registrada');
        await cargarCatalogos(); // trae los costos actualizados
        await cargarDia();
    } catch (err) {
        console.error(err);
        alert('❌ Error: ' + err.message);
    } finally {
        btn.textContent = textoOriginal;
        btn.disabled = proveedoresLista.length === 0;
    }
}

function renderCompras(compras) {
    const cont = document.getElementById('lista-compras');
    cont.innerHTML = '';
    if (compras.length === 0) {
        cont.innerHTML = '<p class="px-4 py-6 text-center text-sm text-gray-500">No hay compras registradas este día</p>';
        return;
    }
    compras.forEach(c => {
        const anulada = c.estado === 'anulada';
        const items = (c.compra_items || [])
            .map(it => `<li>${formatCantidad(it.cantidad)} ×${escapeHtml(it.productos?.nombre || '(producto)')} a ${formatCurrency(it.costo_unitario)}</li>`)
            .join('');
        const div = document.createElement('div');
        div.className = 'px-4 py-3' + (anulada ? ' opacity-60' : '');
        div.innerHTML = `
            <div class="flex justify-between items-start gap-3">
                <div>
                    <p class="text-sm font-semibold text-gray-900">${escapeHtml(c.proveedores?.nombre || '(proveedor)')}
                        ${anulada ? '<span class="ml-2 px-2 text-xs rounded-full bg-gray-200 text-gray-600">anulada</span>' : ''}</p>
                    <ul class="mt-1 text-sm text-gray-600 list-disc list-inside">${items}</ul>
                </div>
                <div class="text-right">
                    <p class="text-base font-bold text-gray-900 ${anulada ? 'line-through' : ''}">${formatCurrency(c.total)}</p>
                    ${anulada ? '' : `<button onclick="anularCompra('${c.id}')" class="mt-1 text-sm text-red-600 hover:text-red-800">Anular</button>`}
                </div>
            </div>
        `;
        cont.appendChild(div);
    });
}

window.anularCompra = async function(id) {
    const c = comprasPorId.get(id);
    if (!confirm(`¿Anular la compra de ${formatCurrency(c?.total)}?\nBaja tu saldo con el proveedor y queda registrada como anulada.`)) return;

    const { error } = await window.supabaseClient.rpc('anular_compra', { p_compra_id: id });
    if (error) {
        console.error(error);
        alert('❌ Error: ' + error.message);
        return;
    }
    await cargarDia();
};
