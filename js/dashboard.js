// Dashboard functionality
document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    
    mobileMenuBtn.addEventListener('click', () => {
        mobileMenu.classList.toggle('hidden');
    });

    // Set default dates (current month)
    const today = new Date();
    const firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
    const lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
    
    document.getElementById('date-from').valueAsDate = firstDay;
    document.getElementById('date-to').valueAsDate = lastDay;

    // Load initial data
    await loadDashboardData();

    // Filter button
    document.getElementById('apply-filter').addEventListener('click', async () => {
        await loadDashboardData();
    });

    // Period filter change
    document.getElementById('period-filter').addEventListener('change', function() {
        const period = this.value;
        const dateFrom = document.getElementById('date-from');
        const dateTo = document.getElementById('date-to');
        
        const now = new Date();
        
        switch(period) {
            case 'current':
                dateFrom.valueAsDate = new Date(now.getFullYear(), now.getMonth(), 1);
                dateTo.valueAsDate = new Date(now.getFullYear(), now.getMonth() + 1, 0);
                break;
            case 'last':
                dateFrom.valueAsDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
                dateTo.valueAsDate = new Date(now.getFullYear(), now.getMonth(), 0);
                break;
            case 'quarter':
                const quarterStart = new Date(now.getFullYear(), Math.floor(now.getMonth() / 3) * 3, 1);
                dateFrom.valueAsDate = quarterStart;
                dateTo.valueAsDate = now;
                break;
            case 'year':
                dateFrom.valueAsDate = new Date(now.getFullYear(), 0, 1);
                dateTo.valueAsDate = now;
                break;
        }
    });
});

async function loadDashboardData() {
    const dateFrom = document.getElementById('date-from').value;
    const dateTo = document.getElementById('date-to').value;

    try {
        // Fetch sales data
        const { data: ventas, error } = await window.supabaseClient
            .from('ventas')
            .select(`
                *,
                clientes(nombre),
                productos(nombre, costo, precio_venta)
            `)
            .gte('fecha', dateFrom)
            .lte('fecha', dateTo)
            .order('fecha', { ascending: false })
            .limit(50);

        if (error) throw error;

        // Calculate statistics
        let totalVentas = 0;
        let totalCosto = 0;
        let uniqueClientes = new Set();
        let totalProductos = 0;

        ventas.forEach(venta => {
            totalVentas += venta.total;
            totalCosto += (venta.productos?.costo || 0) * venta.cantidad;
            uniqueClientes.add(venta.cliente_id);
            totalProductos += venta.cantidad;
        });

        const margenGanancia = totalVentas > 0 
            ? ((totalVentas - totalCosto) / totalVentas * 100).toFixed(1)
            : 0;

        // Update stats cards
        document.getElementById('total-ventas').textContent = formatCurrency(totalVentas);
        document.getElementById('margen-ganancia').textContent = `${margenGanancia}%`;
        document.getElementById('clientes-activos').textContent = uniqueClientes.size;
        document.getElementById('productos-vendidos').textContent = totalProductos;

        // Update table
        const tableBody = document.getElementById('ventas-table');
        tableBody.innerHTML = '';

        ventas.slice(0, 10).forEach(venta => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${formatDate(venta.fecha)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${venta.clientes?.nombre || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${venta.productos?.nombre || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${venta.cantidad}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-900">
                    ${formatCurrency(venta.total)}
                </td>
            `;
            tableBody.appendChild(row);
        });

    } catch (error) {
        console.error('Error loading dashboard data:', error);
        alert('Error al cargar los datos. Verifica la conexión con Supabase.');
    }
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
        style: 'currency',
        currency: 'ARS'
    }).format(amount);
}

function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('es-AR');
}
