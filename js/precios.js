// Precios functionality
document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', () => {
            mobileMenu.classList.toggle('hidden');
        });
    }

    // Load products
    await loadProductos();
    initModalLogic(); // Inicializar modal después de cargar DOM
});

async function loadProductos() {
    try {
        const { data: productos, error } = await window.supabaseClient
            .from('productos')
            .select('*')
            .order('nombre');

        if (error) throw error;

        const tableBody = document.getElementById('productos-table');
        if (!tableBody) return;
        
        tableBody.innerHTML = '';

        productos.forEach(producto => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">${producto.nombre}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${producto.categoria || '-'}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatCurrency(producto.costo)}</td>
                
                <td class="px-6 py-4 whitespace-nowrap text-sm text-green-700 font-semibold">
                    ${producto.precio_minorista ? formatCurrency(producto.precio_minorista) : '-'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-blue-700 font-semibold">
                    ${producto.precio_mayorista ? formatCurrency(producto.precio_mayorista) : '-'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-purple-700 font-semibold">
                    ${producto.precio_distribuidor ? formatCurrency(producto.precio_distribuidor) : '-'}
                </td>
                
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <button onclick="editarPrecios('${producto.id}')" class="text-blue-600 hover:text-blue-800 mr-3">Editar</button>
                </td>
            `;
            tableBody.appendChild(row);
        });

    } catch (error) {
        console.error('Error loading products:', error);
    }
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS'
    }).format(amount || 0);
}

// --- LÓGICA DEL MODAL (Separada y limpia) ---
function initModalLogic() {
    const modal = document.getElementById('modal-producto');
    const btnNuevo = document.getElementById('btn-nuevo-producto');
    const btnCancelar = document.getElementById('btn-cancelar');
    const formProducto = document.getElementById('form-producto');

    if (!modal || !btnNuevo || !formProducto) return;

    // Abrir modal
    btnNuevo.addEventListener('click', () => {
        modal.classList.remove('hidden');
        setTimeout(() => document.getElementById('prod-nombre')?.focus(), 100);
    });

    // Cerrar modal
    if (btnCancelar) {
        btnCancelar.addEventListener('click', () => {
            modal.classList.add('hidden');
            formProducto.reset();
        });
    }

    // Cerrar al hacer clic fuera
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.classList.add('hidden');
            formProducto.reset();
        }
    });

    // Guardar producto
    formProducto.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        const btnSubmit = formProducto.querySelector('button[type="submit"]');
        const originalText = btnSubmit.textContent;
        btnSubmit.textContent = 'Guardando...';
        btnSubmit.disabled = true;

        try {
            const nuevoProducto = {
                nombre: document.getElementById('prod-nombre').value.trim(),
                categoria: document.getElementById('prod-categoria').value.trim() || null,
                costo: parseFloat(document.getElementById('prod-costo').value) || 0,
                precio_venta: parseFloat(document.getElementById('prod-precio').value) || null,
                precio_minorista: parseFloat(document.getElementById('prod-p-minorista').value) || null,
                precio_mayorista: parseFloat(document.getElementById('prod-p-mayorista').value) || null,
                precio_distribuidor: parseFloat(document.getElementById('prod-p-distribuidor').value) || null
            };

            const { error } = await window.supabaseClient.from('productos').insert([nuevoProducto]);
            
            if (error) throw error;

            modal.classList.add('hidden');
            formProducto.reset();
            loadProductos();
            
        } catch (err) {
            console.error(err);
            alert('❌ Error al guardar: ' + err.message);
        } finally {
            btnSubmit.textContent = originalText;
            btnSubmit.disabled = false;
        }
    });
}
