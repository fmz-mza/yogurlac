// Clientes functionality
document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', () => {
            mobileMenu.classList.toggle('hidden');
        });
    }

    // Load clients
    await loadClientes();
    initClientModals();
});

async function loadClientes(searchTerm = '', listaPrecio = '') {
    try {
        let query = window.supabaseClient.from('clientes').select('*');

        if (searchTerm) {
            query = query.or(`nombre.ilike.%${searchTerm}%,telefono.ilike.%${searchTerm}%`);
        }

        if (listaPrecio) {
            query = query.eq('lista_precio', listaPrecio);
        }

        const { data: clientes, error } = await query.order('nombre');
        if (error) throw error;

        const tableBody = document.getElementById('clientes-table');
        if (!tableBody) return;
        
        tableBody.innerHTML = '';

        clientes.forEach(cliente => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">${cliente.nombre}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${cliente.telefono || 'N/A'}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${cliente.direccion || 'N/A'}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${getListaPrecioColor(cliente.lista_precio)}">
                        ${cliente.lista_precio || 'Sin asignar'}
                    </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-bold ${cliente.saldo > 0 ? 'text-red-600' : 'text-green-600'}">
                    ${formatCurrency(cliente.saldo || 0)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 flex gap-3">
                    <button onclick="abrirModalEdicion('${cliente.id}')" class="text-blue-600 hover:text-blue-800 font-medium">✏️ Editar</button>
                    <button onclick="abrirModalMovimiento('${cliente.id}', '${cliente.nombre.replace(/'/g, "\\'")}')" class="text-green-600 hover:text-green-800 font-medium">💳 Saldo</button>
                    <button onclick="abrirHistorial('${cliente.id}', '${cliente.nombre.replace(/'/g, "\\'")}')" class="text-gray-600 hover:text-gray-900 font-medium">📜 Historial</button>
                </td>
            `;
            tableBody.appendChild(row);
        });

    } catch (error) {
        console.error('Error loading clients:', error);
    }
}

function getListaPrecioColor(lista) {
    const colors = {
        'minorista': 'bg-green-100 text-green-800',
        'mayorista': 'bg-blue-100 text-blue-800',
        'distribuidor': 'bg-purple-100 text-purple-800'
    };
    return colors[lista] || 'bg-gray-100 text-gray-800';
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(amount || 0);
}

// --- LÓGICA DE MODALES ---
function initClientModals() {
    // Modal Nuevo Cliente
    const btnNuevoCli = document.getElementById('btn-nuevo-cliente');
    const modalCli = document.getElementById('modal-cliente');
    const formCliente = document.getElementById('form-cliente');
    const btnCancelCli = document.getElementById('btn-cancelar-cli');

    if (btnNuevoCli && modalCli) {
        btnNuevoCli.addEventListener('click', () => {
            formCliente.reset();
            document.getElementById('cli-id-edit').value = ''; // Limpiar ID oculto
            modalCli.querySelector('h3').textContent = 'Nuevo Cliente';
            modalCli.classList.remove('hidden');
        });
    }

    if (btnCancelCli && modalCli) {
        btnCancelCli.addEventListener('click', () => modalCli.classList.add('hidden'));
    }

    // Formulario Unificado (Crear / Editar)
    if (formCliente) {
        formCliente.addEventListener('submit', async (e) => {
            e.preventDefault();
            const btnSubmit = formCliente.querySelector('button[type="submit"]');
            const originalText = btnSubmit.textContent;
            btnSubmit.textContent = 'Guardando...';
            btnSubmit.disabled = true;

            try {
                const clienteId = document.getElementById('cli-id-edit').value;
                const datosCliente = {
                    nombre: document.getElementById('cli-nombre').value.trim(),
                    telefono: document.getElementById('cli-telefono').value.trim() || null,
                    direccion: document.getElementById('cli-direccion').value.trim() || null,
                    lista_precio: document.getElementById('cli-lista').value
                };

                let error;
                if (clienteId) {
                    // EDICIÓN
                    const res = await window.supabaseClient.from('clientes').update(datosCliente).eq('id', clienteId);
                    error = res.error;
                } else {
                    // CREACIÓN
                    datosCliente.saldo = 0;
                    const res = await window.supabaseClient.from('clientes').insert([datosCliente]);
                    error = res.error;
                }

                if (error) throw error;

                alert(`✅ Cliente ${clienteId ? 'actualizado' : 'creado'} correctamente`);
                modalCli.classList.add('hidden');
                formCliente.reset();
                loadClientes();

            } catch (err) {
                console.error(err);
                alert('❌ Error: ' + err.message);
            } finally {
                btnSubmit.textContent = originalText;
                btnSubmit.disabled = false;
            }
        });
    }

    // Modal Movimientos (Cuenta Corriente)
    const formMov = document.getElementById('form-movimiento');
    if (formMov) {
        formMov.addEventListener('submit', async (e) => {
            e.preventDefault();
            const btnSubmit = formMov.querySelector('button[type="submit"]');
            const originalText = btnSubmit.textContent;
            btnSubmit.textContent = 'Procesando...';
            btnSubmit.disabled = true;

            try {
                const clienteId = document.getElementById('mov-cliente-id').value;
                const tipo = document.getElementById('mov-tipo').value;
                const monto = parseFloat(document.getElementById('mov-monto').value);
                const concepto = document.getElementById('mov-concepto').value;

                // Una sola llamada: el servidor actualiza el saldo y guarda el movimiento en el historial
                const { data: nuevoSaldo, error } = await window.supabaseClient.rpc('registrar_movimiento_cliente', {
                    p_cliente_id: clienteId,
                    p_tipo: tipo,
                    p_monto: monto,
                    p_concepto: concepto
                });
                if (error) throw error;

                alert(`✅ Movimiento registrado. Nuevo saldo: ${formatCurrency(nuevoSaldo)}`);
                document.getElementById('modal-movimiento').classList.add('hidden');
                formMov.reset();
                loadClientes();

            } catch (err) {
                alert('❌ Error: ' + err.message);
            } finally {
                btnSubmit.textContent = originalText;
                btnSubmit.disabled = false;
            }
        });
    }
}

// Funciones Globales para botones onclick en HTML
window.abrirModalEdicion = async function(id) {
    const modal = document.getElementById('modal-cliente');
    const form = document.getElementById('form-cliente');
    
    const { data, error } = await window.supabaseClient.from('clientes').select('*').eq('id', id).single();
    if (error || !data) return alert('Error al cargar datos del cliente');

    document.getElementById('cli-id-edit').value = data.id;
    document.getElementById('cli-nombre').value = data.nombre;
    document.getElementById('cli-telefono').value = data.telefono || '';
    document.getElementById('cli-direccion').value = data.direccion || '';
    document.getElementById('cli-lista').value = data.lista_precio || 'minorista';
    
    modal.querySelector('h3').textContent = 'Editar Cliente';
    modal.classList.remove('hidden');
};

window.abrirModalMovimiento = function(id, nombre) {
    const modal = document.getElementById('modal-movimiento');
    document.getElementById('mov-cliente-id').value = id;
    document.getElementById('mov-cliente-nombre').textContent = `Cliente: ${nombre}`;
    document.getElementById('form-movimiento').reset();
    modal.classList.remove('hidden');
};

window.cerrarModalMovimiento = function() {
    document.getElementById('modal-movimiento').classList.add('hidden');
};

// Historial de la cuenta corriente de un cliente (tabla movimientos_cliente).
// Las ventas y las compras a cuenta suman deuda; los pagos la restan.
window.abrirHistorial = async function(id, nombre) {
    document.getElementById('hist-cliente-nombre').textContent = `Cliente: ${nombre}`;
    const tbody = document.getElementById('hist-body');
    tbody.innerHTML = '<tr><td colspan="5" class="px-3 py-6 text-center text-gray-500">Cargando...</td></tr>';
    document.getElementById('modal-historial').classList.remove('hidden');

    const { data: movimientos, error } = await window.supabaseClient
        .from('movimientos_cliente')
        .select('fecha, tipo, monto, concepto, created_at')
        .eq('cliente_id', id)
        .order('created_at', { ascending: true });

    tbody.innerHTML = '';

    if (error) {
        console.error('Error cargando historial:', error);
        tbody.innerHTML = '<tr><td colspan="5" class="px-3 py-6 text-center text-red-600">No se pudo cargar el historial</td></tr>';
        return;
    }
    if (!movimientos.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="px-3 py-6 text-center text-gray-500">Este cliente todavía no tiene movimientos</td></tr>';
        return;
    }

    const etiquetas = { venta: '🛒 Venta', compra: '🛒 Compra a cuenta', pago: '💰 Pago' };

    // Saldo acumulado en orden cronológico; se muestra del más nuevo al más viejo
    let saldo = 0;
    const filas = movimientos.map(m => {
        const monto = Number(m.monto);
        const firmado = m.tipo === 'pago' ? -monto : monto;
        saldo += firmado;
        return { m, firmado, saldo };
    }).reverse();

    filas.forEach(({ m, firmado, saldo }) => {
        const tr = document.createElement('tr');
        const celdas = [
            [new Date(m.fecha + 'T00:00:00').toLocaleDateString('es-AR'), 'text-gray-900'],
            [etiquetas[m.tipo] || m.tipo, 'text-gray-900'],
            [m.concepto || '-', 'text-gray-600'],
            [(firmado < 0 ? '-' : '+') + formatCurrency(Math.abs(firmado)), firmado < 0 ? 'text-green-600 text-right font-medium' : 'text-red-600 text-right font-medium'],
            [formatCurrency(saldo), 'text-gray-900 text-right font-semibold']
        ];
        celdas.forEach(([texto, clases]) => {
            const td = document.createElement('td');
            td.className = `px-3 py-2 whitespace-nowrap text-sm ${clases}`;
            td.textContent = texto; // textContent: el concepto lo escribe el usuario
            tr.appendChild(td);
        });
        tbody.appendChild(tr);
    });
};

window.cerrarHistorial = function() {
    document.getElementById('modal-historial').classList.add('hidden');
};
