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
        // Consulta CORRECTA: Ventas -> Detalles -> Productos
        const { data: ventas, error } = await window.supabaseClient
            .from('ventas')
            .select(`
                id, 
                fecha, 
                total, 
                cliente_id,
                clientes ( nombre ),
                venta_detalles (
                    cantidad,
                    precio_unitario,
                    productos ( nombre, costo )
                )
            `)
            .gte('fecha', dateFrom)
            .lte('fecha', dateTo)
            .order('fecha', { ascending: false })
            .limit(50);

        if (error) throw error;

        let totalVentas = 0;
        let totalCosto = 0;
        let uniqueClientes = new Set();
        let totalProductos = 0;
        const filasTabla = [];

        ventas.forEach(v => {
            totalVentas += v.total || 0;
            if (v.cliente_id) uniqueClientes.add(v.cliente_id);

            // Procesar detalles anidados
            if (v.venta_detalles) {
                v.venta_detalles.forEach(d => {
                    const cant = d.cantidad || 0;
                    const costoUnit = d.productos?.costo || 0;
                    
                    totalCosto += costoUnit * cant;
                    totalProductos += cant;

                    filasTabla.push({
                        fecha: v.fecha,
                        cliente: v.clientes?.nombre || 'N/A',
                        producto: d.productos?.nombre || 'N/A',
                        cantidad: cant,
                        total: v.total
                    });
                });
            }
        });

        const margen = totalVentas > 0 
            ? ((totalVentas - totalCosto) / totalVentas * 100).toFixed(1) 
            : 0;

        // Actualizar Tarjetas
        document.getElementById('total-ventas').textContent = formatCurrency(totalVentas);
        document.getElementById('margen-ganancia').textContent = `${margen}%`;
        document.getElementById('clientes-activos').textContent = uniqueClientes.size;
        document.getElementById('productos-vendidos').textContent = totalProductos;

        // Renderizar Tabla
        const tbody = document.getElementById('ventas-table');
        tbody.innerHTML = '';
        
        filasTabla.slice(0, 10).forEach(f => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td class="px-6 py-4 text-sm">${formatDate(f.fecha)}</td>
                <td class="px-6 py-4 text-sm">${f.cliente}</td>
                <td class="px-6 py-4 text-sm">${f.producto}</td>
                <td class="px-6 py-4 text-sm">${f.cantidad}</td>
                <td class="px-6 py-4 text-sm font-bold">${formatCurrency(f.total)}</td>
            `;
            tbody.appendChild(tr);
        });

    } catch (err) {
        console.error('Error Dashboard:', err);
        alert('Error al cargar dashboard: ' + err.message);
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
