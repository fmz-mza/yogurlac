// Precios functionality
document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    
    mobileMenuBtn.addEventListener('click', () => {
        mobileMenu.classList.toggle('hidden');
    });

    // Load products
    await loadProductos();
});

async function loadProductos() {
    try {
        const { data: productos, error } = await window.supabaseClient
            .from('productos')
            .select('*')
            .order('nombre');

        if (error) throw error;

        const tableBody = document.getElementById('productos-table');
        tableBody.innerHTML = '';

        productos.forEach(producto => {
    const row = document.createElement('tr');
    row.innerHTML = `
        <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">${producto.nombre}</td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${producto.categoria || '-'}</td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatCurrency(producto.costo)}</td>
        
        <!-- NUEVAS CELDAS DE PRECIOS POR LISTA -->
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
            <button onclick="editarPrecios('${producto.id}')" class="text-blue-600 hover:text-blue-800 mr-3">Editar Precios</button>
        </td>
    `;
    tableBody.appendChild(row);
});

    } catch (error) {
        console.error('Error loading products:', error);
    }
}

function getMargenColor(margen) {
    if (margen >= 30) return 'bg-green-100 text-green-800';
    if (margen >= 15) return 'bg-yellow-100 text-yellow-800';
    return 'bg-red-100 text-red-800';
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS'
    }).format(amount);
}
// Lógica del Modal
const modal = document.getElementById('modal-producto');
const btnNuevo = document.getElementById('btn-nuevo-producto');
const btnCancelar = document.getElementById('btn-cancelar');
const formProducto = document.getElementById('form-producto');

// Abrir modal
btnNuevo.addEventListener('click', () => {
    modal.classList.remove('hidden');
});

// Cerrar modal
btnCancelar.addEventListener('click', () => {
    modal.classList.add('hidden');
    formProducto.reset();
});

// Guardar producto
formProducto.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const nuevoProducto = {
        nombre: document.getElementById('prod-nombre').value,
        categoria: document.getElementById('prod-categoria').value,
        costo: parseFloat(document.getElementById('prod-costo').value),
        precio_venta: parseFloat(document.getElementById('prod-precio').value)
    };

    try {
        const { error } = await window.supabaseClient
            .from('productos')
            .insert([nuevoProducto]);

        if (error) throw error;

        alert('✅ Producto agregado correctamente');
        modal.classList.add('hidden');
        formProducto.reset();
        loadProductos(); // Recargar tabla
        
    } catch (err) {
        console.error(err);
        alert('❌ Error al guardar: ' + err.message);
    }
});
