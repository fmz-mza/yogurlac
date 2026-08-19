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
            const margen = producto.costo > 0 
                ? ((producto.precio_venta - producto.costo) / producto.costo * 100).toFixed(1)
                : 0;

            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    ${producto.nombre}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${producto.categoria || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${formatCurrency(producto.costo)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-900">
                    ${formatCurrency(producto.precio_venta)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full 
                        ${getMargenColor(margen)}">
                        ${margen}%
                    </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <button class="text-blue-600 hover:text-blue-800 mr-3">Editar</button>
                    <button class="text-red-600 hover:text-red-800">Eliminar</button>
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
