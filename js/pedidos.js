// Pedidos: se cargan una sola vez; de ahí salen la compra a Yogurlac y la entrega.
// Estados: pendiente -> entregado (o cancelado). Aquí solo se crean, editan y cancelan.
let clientesLista = [];   // [{id, nombre}]
let productosLista = [];  // productos activos [{id, nombre}]
const pedidosPorId = new Map();

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

document.addEventListener('DOMContentLoaded', async () => {
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', () => mobileMenu.classList.toggle('hidden'));
    }

    const inputFecha = document.getElementById('fecha-pedidos');
    inputFecha.value = fechaLocal();
    inputFecha.addEventListener('change', cargarPedidos);
    document.getElementById('btn-hoy').addEventListener('click', () => { inputFecha.value = fechaLocal(); cargarPedidos(); });
    document.getElementById('btn-dia-anterior').addEventListener('click', () => { inputFecha.value = sumarDias(inputFecha.value, -1); cargarPedidos(); });
    document.getElementById('btn-dia-siguiente').addEventListener('click', () => { inputFecha.value = sumarDias(inputFecha.value, 1); cargarPedidos(); });

    initModalPedido();
    await cargarCatalogos();
    await cargarPedidos();
});

async function cargarCatalogos() {
    const [{ data: clientes, error: e1 }, { data: productos, error: e2 }] = await Promise.all([
        window.supabaseClient.from('clientes').select('id, nombre').order('nombre'),
        window.supabaseClient.from('productos').select('id, nombre').eq('activo', true).order('nombre')
    ]);
    if (e1 || e2) console.error('Error cargando catálogos:', e1 || e2);
    clientesLista = clientes || [];
    productosLista = productos || [];

    const select = document.getElementById('ped-cliente');
    clientesLista.forEach(c => {
        const opt = document.createElement('option');
        opt.value = c.id;
        opt.textContent = c.nombre;
        select.appendChild(opt);
    });
}

async function cargarPedidos() {
    const fecha = document.getElementById('fecha-pedidos').value;
    if (!fecha) return;
    document.getElementById('fecha-legible').textContent = fechaLegible(fecha);

    const { data, error } = await window.supabaseClient
        .from('pedidos')
        .select('id, cliente_id, fecha_entrega, estado, observaciones, created_at, clientes(nombre), pedido_items(producto_id, cantidad, productos(nombre))')
        .eq('fecha_entrega', fecha)
        .order('created_at', { ascending: true });

    if (error) {
        console.error('Error cargando pedidos:', error);
        document.getElementById('lista-pedidos').innerHTML =
            '<div class="bg-white rounded-lg shadow p-6 text-center text-red-600">No se pudieron cargar los pedidos</div>';
        return;
    }

    pedidosPorId.clear();
    (data || []).forEach(p => pedidosPorId.set(p.id, p));
    renderResumenCompra(data || []);
    renderPedidos(data || []);
}

// Suma de cantidades por producto de los pedidos PENDIENTES del día
function renderResumenCompra(pedidos) {
    const tbody = document.getElementById('resumen-compra-body');
    const totales = new Map(); // nombre -> cantidad
    pedidos.filter(p => p.estado === 'pendiente').forEach(p => {
        (p.pedido_items || []).forEach(it => {
            const nombre = it.productos?.nombre || '(producto eliminado)';
            totales.set(nombre, (totales.get(nombre) || 0) + it.cantidad);
        });
    });

    tbody.innerHTML = '';
    if (totales.size === 0) {
        tbody.innerHTML = '<tr><td colspan="2" class="px-4 py-6 text-center text-sm text-gray-500">No hay pedidos pendientes para este día</td></tr>';
        return;
    }
    [...totales.entries()].sort((a, b) => a[0].localeCompare(b[0], 'es')).forEach(([nombre, cant]) => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td class="px-4 py-2 text-sm text-gray-900">${escapeHtml(nombre)}</td>
            <td class="px-4 py-2 text-sm text-right font-semibold text-gray-900">${cant}</td>
        `;
        tbody.appendChild(tr);
    });
}

function renderPedidos(pedidos) {
    const cont = document.getElementById('lista-pedidos');
    cont.innerHTML = '';

    if (pedidos.length === 0) {
        cont.innerHTML = '<div class="bg-white rounded-lg shadow p-8 text-center text-gray-500">No hay pedidos para este día</div>';
        return;
    }

    const estilos = {
        pendiente: 'bg-yellow-100 text-yellow-800',
        entregado: 'bg-green-100 text-green-800',
        cancelado: 'bg-gray-200 text-gray-600'
    };

    pedidos.forEach(p => {
        const items = (p.pedido_items || [])
            .map(it => `<li>${it.cantidad} × ${escapeHtml(it.productos?.nombre || '(producto eliminado)')}</li>`)
            .join('');
        const acciones = p.estado === 'pendiente' ? `
            <div class="flex gap-3 mt-3">
                <button onclick="editarPedido('${p.id}')" class="text-blue-600 hover:text-blue-800 text-sm font-medium">✏️ Editar</button>
                <button onclick="cancelarPedido('${p.id}')" class="text-red-600 hover:text-red-800 text-sm font-medium">✖ Cancelar pedido</button>
            </div>` : '';

        const card = document.createElement('div');
        card.className = 'bg-white rounded-lg shadow p-4' + (p.estado === 'cancelado' ? ' opacity-60' : '');
        card.innerHTML = `
            <div class="flex justify-between items-start gap-3">
                <h4 class="text-base font-semibold text-gray-900">${escapeHtml(p.clientes?.nombre || '(cliente eliminado)')}</h4>
                <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${estilos[p.estado] || estilos.cancelado}">${escapeHtml(p.estado)}</span>
            </div>
            <ul class="mt-2 text-sm text-gray-700 list-disc list-inside">${items}</ul>
            ${p.observaciones ? `<p class="mt-2 text-sm text-gray-500 italic">${escapeHtml(p.observaciones)}</p>` : ''}
            ${acciones}
        `;
        cont.appendChild(card);
    });
}

// --- MODAL ---
function initModalPedido() {
    const modal = document.getElementById('modal-pedido');
    const form = document.getElementById('form-pedido');

    document.getElementById('btn-nuevo-pedido').addEventListener('click', () => {
        abrirModalPedido(null);
    });
    document.getElementById('btn-cancelar-pedido-modal').addEventListener('click', () => modal.classList.add('hidden'));
    document.getElementById('btn-agregar-linea').addEventListener('click', () => agregarLinea());

    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = form.querySelector('button[type="submit"]');
        const textoOriginal = btn.textContent;

        const items = [...document.querySelectorAll('#ped-lineas [data-linea]')]
            .map(l => ({
                producto_id: l.querySelector('select').value,
                cantidad: parseInt(l.querySelector('input').value, 10)
            }))
            .filter(i => i.producto_id && i.cantidad > 0);

        if (items.length === 0) {
            alert('Agregá al menos un producto con cantidad.');
            return;
        }

        btn.textContent = 'Guardando...';
        btn.disabled = true;
        try {
            const id = document.getElementById('ped-id-edit').value;
            const fecha = document.getElementById('ped-fecha').value;
            const obs = document.getElementById('ped-obs').value;

            const { error } = id
                ? await window.supabaseClient.rpc('actualizar_pedido', { p_pedido_id: id, p_fecha: fecha, p_items: items, p_observaciones: obs })
                : await window.supabaseClient.rpc('crear_pedido', {
                    p_cliente_id: document.getElementById('ped-cliente').value,
                    p_fecha: fecha, p_items: items, p_observaciones: obs
                });
            if (error) throw error;

            modal.classList.add('hidden');
            // Mostrar el día del pedido guardado, para verlo enseguida
            document.getElementById('fecha-pedidos').value = fecha;
            await cargarPedidos();
        } catch (err) {
            console.error(err);
            alert('❌ Error: ' + err.message);
        } finally {
            btn.textContent = textoOriginal;
            btn.disabled = false;
        }
    });
}

function abrirModalPedido(pedido) {
    const modal = document.getElementById('modal-pedido');
    const selectCliente = document.getElementById('ped-cliente');
    document.getElementById('form-pedido').reset();
    document.getElementById('ped-lineas').innerHTML = '';

    if (pedido) {
        document.getElementById('modal-pedido-titulo').textContent = 'Editar Pedido';
        document.getElementById('ped-id-edit').value = pedido.id;
        selectCliente.value = pedido.cliente_id;
        selectCliente.disabled = true; // el cliente no se cambia: se cancela y se crea otro
        document.getElementById('ped-fecha').value = pedido.fecha_entrega;
        document.getElementById('ped-obs').value = pedido.observaciones || '';
        (pedido.pedido_items || []).forEach(it => agregarLinea(it.producto_id, it.cantidad));
    } else {
        document.getElementById('modal-pedido-titulo').textContent = 'Nuevo Pedido';
        document.getElementById('ped-id-edit').value = '';
        selectCliente.disabled = false;
        document.getElementById('ped-fecha').value = document.getElementById('fecha-pedidos').value || fechaLocal();
        agregarLinea();
    }
    modal.classList.remove('hidden');
}

function agregarLinea(productoId = '', cantidad = '') {
    const cont = document.getElementById('ped-lineas');
    const fila = document.createElement('div');
    fila.setAttribute('data-linea', '');
    fila.className = 'flex gap-2 items-center';

    const select = document.createElement('select');
    select.className = 'flex-1 border border-gray-300 rounded-md px-3 py-2 bg-white';
    const vacio = document.createElement('option');
    vacio.value = '';
    vacio.textContent = '-- Producto --';
    select.appendChild(vacio);
    productosLista.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.nombre;
        select.appendChild(opt);
    });
    select.value = productoId;

    const input = document.createElement('input');
    input.type = 'number';
    input.min = '1';
    input.step = '1';
    input.placeholder = 'Cant.';
    input.className = 'w-24 border border-gray-300 rounded-md px-3 py-2';
    input.value = cantidad;

    const quitar = document.createElement('button');
    quitar.type = 'button';
    quitar.textContent = '✕';
    quitar.setAttribute('aria-label', 'Quitar producto');
    quitar.className = 'text-red-500 hover:text-red-700 px-2';
    quitar.addEventListener('click', () => {
        if (cont.querySelectorAll('[data-linea]').length > 1) fila.remove();
        else { select.value = ''; input.value = ''; }
    });

    fila.append(select, input, quitar);
    cont.appendChild(fila);
}

window.editarPedido = function(id) {
    const p = pedidosPorId.get(id);
    if (p) abrirModalPedido(p);
};

window.cancelarPedido = async function(id) {
    const p = pedidosPorId.get(id);
    const nombre = p?.clientes?.nombre || '';
    if (!confirm(`¿Cancelar el pedido de "${nombre}"?`)) return;

    const { error } = await window.supabaseClient.rpc('cancelar_pedido', { p_pedido_id: id });
    if (error) {
        console.error(error);
        alert('❌ Error: ' + error.message);
        return;
    }
    await cargarPedidos();
};
