// Proveedores functionality
document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    
    mobileMenuBtn.addEventListener('click', () => {
        mobileMenu.classList.toggle('hidden');
    });

    // Load data
    await loadVentasDiarias();
    await loadCuentaCorriente();
});

async function loadVentasDiarias() {
    try {
        const today = new Date().toISOString().split('T')[0];
        
        const { data: ventas, error } = await supabase
            .from('ventas_diarias')
            .select(`
                *,
                proveedores(nombre),
                productos(nombre)
            `)
            .eq('fecha', today)
            .order('created_at', { ascending: false });

        if (error) throw error;

        let totalVentas = 0;
        let totalCostos = 0;

        const tableBody = document.getElementById('ventas-diarias-table');
        tableBody.innerHTML = '';

        ventas.forEach(venta => {
            const margen = venta.costo_unitario > 0 
                ? ((venta.precio_venta - venta.costo_unitario) / venta.costo_unitario * 100).toFixed(1)
                : 0;
            
            const subtotalVenta = venta.precio_venta * venta.cantidad;
            const subtotalCosto = venta.costo_unitario * venta.cantidad;
            
            totalVentas += subtotalVenta;
            totalCostos += subtotalCosto;

            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${formatDate(venta.fecha)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${venta.proveedores?.nombre || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${venta.productos?.nombre || 'N/A'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${venta.cantidad}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${formatCurrency(venta.costo_unitario)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-900">
                    ${formatCurrency(venta.precio_venta)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full 
                        ${margen >= 20 ? 'bg-green-100 text-green-800' : 'bg-yellow-100 text-yellow-800'}">
                        ${margen}%
                    </span>
                </td>
            `;
            tableBody.appendChild(row);
        });

        // Update summary
        const margenTotal = totalVentas > 0 
            ? ((totalVentas - totalCostos) / totalVentas * 100).toFixed(1)
            : 0;

        document.getElementById('ventas-hoy').textContent = formatCurrency(totalVentas);
        document.getElementById('costos-hoy').textContent = formatCurrency(totalCostos);
        document.getElementById('margen-hoy').textContent = `${margenTotal}%`;

    } catch (error) {
        console.error('Error loading daily sales:', error);
    }
}

async function loadCuentaCorriente() {
    try {
        const { data: movimientos, error } = await supabase
            .from('cuenta_corriente')
            .select('*')
            .order('fecha', { ascending: false })
            .limit(50);

        if (error) throw error;

        const tableBody = document.getElementById('cuenta-corriente-table');
        tableBody.innerHTML = '';

        let saldo = 0;

        movimientos.forEach(mov => {
            saldo += (mov.haber || 0) - (mov.debe || 0);

            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${formatDate(mov.fecha)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    ${mov.concepto}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-red-600">
                    ${mov.debe ? formatCurrency(mov.debe) : '-'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-green-600">
                    ${mov.haber ? formatCurrency(mov.haber) : '-'}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-900">
                    ${formatCurrency(saldo)}
                </td>
            `;
            tableBody.appendChild(row);
        });

    } catch (error) {
        console.error('Error loading current account:', error);
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
