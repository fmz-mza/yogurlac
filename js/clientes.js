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
        let query = supabase.from('clientes').select('*');

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
                    <button class="text-blue-600 hover:text-blue-800 mr-3">Editar</button>
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
