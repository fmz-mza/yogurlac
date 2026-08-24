// Clientes functionality
document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    
    mobileMenuBtn.addEventListener('click', () => {
        mobileMenu.classList.toggle('hidden');
    });

    // Load clients
    await loadClientes();

    // Search functionality
    document.getElementById('search-cliente').addEventListener('input', debounce(async (e) => {
        await loadClientes(e.target.value);
    }, 300));

    // Filter by price list
    document.getElementById('filter-lista-precio').addEventListener('change', async (e) => {
        await loadClientes(null, e.target.value);
    });
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
        tableBody.innerHTML = '';

        clientes.forEach(cliente => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    ${cliente.nombre}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${cliente.telefono || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${cliente.direccion || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full 
                        ${getListaPrecioColor(cliente.lista_precio)}">
                        ${cliente.lista_precio || 'Sin asignar'}
                    </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${formatCurrency(cliente.saldo || 0)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                   <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
    <button onclick="abrirModalMovimiento('${cliente.id}', '${cliente.nombre}')" 
            class="text-green-600 hover:text-green-800 mr-3 font-medium flex items-center gap-1 inline-flex">
        💳 Movimiento
    </button>
    <button class="text-blue-600 hover:text-blue-800 mr-3">Editar</button>
</td>
                    <button class="text-red-600 hover:text-red-800">Eliminar</button>
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
    return new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS'
    }).format(amount);
}

function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}
// --- LÓGICA DEL MODAL CLIENTE ---
const modalCli = document.getElementById('modal-cliente');
const btnNuevoCli = document.getElementById('btn-nuevo-cliente');
const btnCancelarCli = document.getElementById('btn-cancelar-cli');
const formCliente = document.getElementById('form-cliente');

if(btnNuevoCli) {
    btnNuevoCli.addEventListener('click', () => modalCli.classList.remove('hidden'));
}

if(btnCancelarCli) {
    btnCancelarCli.addEventListener('click', () => {
        modalCli.classList.add('hidden');
        formCliente.reset();
    });
}

if(formCliente) {
    formCliente.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        const nuevoCliente = {
            nombre: document.getElementById('cli-nombre').value,
            telefono: document.getElementById('cli-telefono').value,
            direccion: document.getElementById('cli-direccion').value,
            lista_precio: document.getElementById('cli-lista').value,
            saldo: 0
        };

        try {
            const { error } = await window.supabaseClient.from('clientes').insert([nuevoCliente]);
            if (error) throw error;

            alert('✅ Cliente agregado correctamente');
            modalCli.classList.add('hidden');
            formCliente.reset();
            loadClientes(); // Recargar tabla
            
        } catch (err) {
            console.error(err);
            alert(' Error al guardar: ' + err.message);
        }
    });
}
// --- LÓGICA DE CUENTA CORRIENTE ---

// Función global para abrir el modal (llamada desde el HTML onclick)
window.abrirModalMovimiento = function(clienteId, clienteNombre) {
    const modal = document.getElementById('modal-movimiento');
    document.getElementById('mov-cliente-id').value = clienteId;
    document.getElementById('mov-cliente-nombre').textContent = `Cliente: ${clienteNombre}`;
    document.getElementById('form-movimiento').reset();
    modal.classList.remove('hidden');
};

window.cerrarModalMovimiento = function() {
    document.getElementById('modal-movimiento').classList.add('hidden');
};

// Manejar el envío del formulario
document.addEventListener('DOMContentLoaded', () => {
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
                const concepto = document.getElementById('mov-concepto').value || (tipo === 'pago' ? 'Pago recibido' : 'Compra a cuenta');

                // 1. Obtener saldo actual
                const { data: clienteActual, error: fetchError } = await window.supabaseClient
                    .from('clientes')
                    .select('saldo')
                    .eq('id', clienteId)
                    .single();

                if (fetchError) throw fetchError;

                // 2. Calcular nuevo saldo
                let nuevoSaldo = clienteActual.saldo || 0;
                if (tipo === 'compra') {
                    nuevoSaldo += monto; // Suma deuda
                } else {
                    nuevoSaldo -= monto; // Resta deuda (pago)
                }

                // 3. Actualizar saldo del cliente
                const { error: updateError } = await window.supabaseClient
                    .from('clientes')
                    .update({ saldo: nuevoSaldo })
                    .eq('id', clienteId);

                if (updateError) throw updateError;

                // 4. (Opcional pero recomendado) Registrar en tabla de movimientos si existe
                // Si tienes una tabla 'movimientos_clientes', descomenta esto:
                /*
                await window.supabaseClient.from('movimientos_clientes').insert([{
                    cliente_id: clienteId,
                    tipo: tipo,
                    monto: monto,
                    concepto: concepto,
                    fecha: new Date().toISOString()
                }]);
                */

                alert(`✅ ${tipo === 'pago' ? 'Pago registrado' : 'Compra registrada'} correctamente.\nNuevo saldo: ${formatCurrency(nuevoSaldo)}`);
                cerrarModalMovimiento();
                loadClientes(); // Recargar tabla para ver saldo actualizado

            } catch (err) {
                console.error(err);
                alert('❌ Error: ' + err.message);
            } finally {
                btnSubmit.textContent = originalText;
                btnSubmit.disabled = false;
            }
        });
    }
});
