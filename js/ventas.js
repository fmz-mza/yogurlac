// Variables globales del carrito
let carrito = [];
let clienteActual = null;
let productosCache = [];

document.addEventListener('DOMContentLoaded', async () => {
    await cargarClientes();
    await cargarProductosBase();
    initEventListeners();
});

async function cargarClientes() {
    const { data } = await window.supabaseClient.from('clientes').select('*').order('nombre');
    const select = document.getElementById('venta-cliente');
    data.forEach(c => {
        const opt = document.createElement('option');
        opt.value = c.id;
        opt.textContent = c.nombre;
        opt.dataset.lista = c.lista_precio || 'minorista';
        select.appendChild(opt);
    });
}

async function cargarProductosBase() {
    const { data } = await window.supabaseClient.from('productos').select('*').order('nombre');
    productosCache = data || [];
}

function initEventListeners() {
    // Al cambiar cliente, habilitar selects y mostrar info
    document.getElementById('venta-cliente').addEventListener('change', (e) => {
        const clientId = e.target.value;
        if (!clientId) {
            deshabilitarFormulario();
            return;
        }
        
        const selectedOpt = e.target.options[e.target.selectedIndex];
        const listaPrecio = selectedOpt.dataset.lista;
        clienteActual = { id: clientId, lista: listaPrecio };
        
        document.getElementById('cliente-info').textContent = `Lista asignada: ${listaPrecio.toUpperCase()}`;
        document.getElementById('cliente-info').classList.remove('hidden');
        
        cargarProductosParaLista(listaPrecio);
        habilitarFormulario();
    });

    // Preview de precio al cambiar producto o cantidad
    ['venta-producto', 'venta-cantidad'].forEach(id => {
        document.getElementById(id).addEventListener('change', actualizarPreview);
    });

    // Agregar al carrito
    document.getElementById('btn-agregar-item').addEventListener('click', agregarAlCarrito);

    // Guardar venta completa
    document.getElementById('btn-guardar-venta').addEventListener('click', guardarVenta);
}

function cargarProductosParaLista(lista) {
    const select = document.getElementById('venta-producto');
    select.innerHTML = '<option value="">-- Seleccionar producto --</option>';
    
    productosCache.forEach(p => {
        // Determinar precio según lista del cliente
        let precio = p.precio_venta; // Fallback
        if (lista === 'minorista' && p.precio_minorista) precio = p.precio_minorista;
        if (lista === 'mayorista' && p.precio_mayorista) precio = p.precio_mayorista;
        if (lista === 'distribuidor' && p.precio_distribuidor) precio = p.precio_distribuidor;

        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = `${p.nombre} ($${formatCurrency(precio)})`;
        opt.dataset.precio = precio;
        opt.dataset.nombre = p.nombre;
        select.appendChild(opt);
    });
}

function actualizarPreview() {
    const prodSelect = document.getElementById('venta-producto');
    const cant = parseInt(document.getElementById('venta-cantidad').value) || 0;
    const precio = parseFloat(prodSelect.options[prodSelect.selectedIndex]?.dataset.precio || 0);
    
    const preview = document.getElementById('precio-preview');
    if (precio > 0 && cant > 0) {
        preview.textContent = `Subtotal estimado: ${formatCurrency(precio * cant)}`;
    } else {
        preview.textContent = '';
    }
}

function agregarAlCarrito() {
    const prodSelect = document.getElementById('venta-producto');
    const productId = prodSelect.value;
    if (!productId) return alert('Selecciona un producto');

    const cantidad = parseInt(document.getElementById('venta-cantidad').value);
    const precio = parseFloat(prodSelect.options[prodSelect.selectedIndex].dataset.precio);
    const nombre = prodSelect.options[prodSelect.selectedIndex].dataset.nombre;

    // Verificar si ya existe en carrito para sumar cantidad
    const existente = carrito.find(item => item.producto_id === productId);
    if (existente) {
        existente.cantidad += cantidad;
        existente.subtotal = existente.cantidad * existente.precio_unitario;
    } else {
        carrito.push({
            producto_id: productId,
            nombre: nombre,
            cantidad: cantidad,
            precio_unitario: precio,
            subtotal: cantidad * precio
        });
    }

    renderizarCarrito();
    // Resetear inputs
    prodSelect.value = "";
    document.getElementById('venta-cantidad').value = 1;
    document.getElementById('precio-preview').textContent = "";
}

function renderizarCarrito() {
    const tbody = document.getElementById('carrito-body');
    const btnGuardar = document.getElementById('btn-guardar-venta');
    
    if (carrito.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="px-6 py-8 text-center text-gray-500">El carrito está vacío</td></tr>';
        btnGuardar.disabled = true;
        actualizarTotal();
        return;
    }

    tbody.innerHTML = '';
    carrito.forEach((item, index) => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td class="px-6 py-4 text-sm">${item.nombre}</td>
            <td class="px-6 py-4 text-sm">${item.cantidad}</td>
            <td class="px-6 py-4 text-sm">${formatCurrency(item.precio_unitario)}</td>
            <td class="px-6 py-4 text-sm font-semibold">${formatCurrency(item.subtotal)}</td>
            <td class="px-6 py-4 text-right">
                <button onclick="eliminarDelCarrito(${index})" class="text-red-600 hover:text-red-800 text-sm">Eliminar</button>
            </td>
        `;
        tbody.appendChild(tr);
    });

    btnGuardar.disabled = false;
    actualizarTotal();
}

window.eliminarDelCarrito = function(index) {
    carrito.splice(index, 1);
    renderizarCarrito();
};

function actualizarTotal() {
    const total = carrito.reduce((sum, item) => sum + item.subtotal, 0);
    document.getElementById('carrito-total').textContent = formatCurrency(total);
}

async function guardarVenta() {
    if (!clienteActual || carrito.length === 0) return;

    const btn = document.getElementById('btn-guardar-venta');
    btn.textContent = 'Guardando...';
    btn.disabled = true;

    try {
        const totalVenta = carrito.reduce((sum, item) => sum + item.subtotal, 0);

        // 1. Crear registro de venta
        const { data: ventaData, error: ventaError } = await window.supabaseClient
            .from('ventas')
            .insert([{
                cliente_id: clienteActual.id,
                total: totalVenta,
                estado: 'pendiente',
                fecha: new Date().toISOString().split('T')[0]
            }])
            .select()
            .single();

        if (ventaError) throw ventaError;

        // 2. Insertar detalles
        const detalles = carrito.map(item => ({
            venta_id: ventaData.id,
            producto_id: item.producto_id,
            cantidad: item.cantidad,
            precio_unitario: item.precio_unitario
        }));

        const { error: detalleError } = await window.supabaseClient
            .from('venta_detalles')
            .insert(detalles);

        if (detalleError) throw detalleError;

        // 3. Actualizar saldo del cliente (suma deuda)
        await window.supabaseClient.rpc('actualizar_saldo_cliente', { 
            p_cliente_id: clienteActual.id, 
            p_monto: totalVenta 
        }).catch(() => {
            // Fallback si no existe la función RPC: update manual
             window.supabaseClient.from('clientes')
                .update({ saldo: window.supabaseClient.from('clientes').select('saldo').eq('id', clienteActual.id).single().then(r => (r.data?.saldo || 0) + totalVenta) })
                .eq('id', clienteActual.id);
        });

        alert('✅ Venta registrada correctamente');
        window.location.href = 'index.html';

    } catch (err) {
        console.error(err);
        alert('❌ Error al guardar: ' + err.message);
        btn.textContent = ' Guardar Venta';
        btn.disabled = false;
    }
}

function habilitarFormulario() {
    document.getElementById('venta-producto').disabled = false;
    document.getElementById('venta-cantidad').disabled = false;
    document.getElementById('btn-agregar-item').disabled = false;
    document.getElementById('venta-producto').classList.remove('bg-gray-100');
    document.getElementById('venta-cantidad').classList.remove('bg-gray-100');
}

function deshabilitarFormulario() {
    document.getElementById('venta-producto').disabled = true;
    document.getElementById('venta-cantidad').disabled = true;
    document.getElementById('btn-agregar-item').disabled = true;
    document.getElementById('cliente-info').classList.add('hidden');
    clienteActual = null;
    carrito = [];
    renderizarCarrito();
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(amount || 0);
}
