// Proveedores: cuenta corriente (lo que se le debe a cada proveedor)
// saldo > 0 = deuda propia con el proveedor. Las compras a cuenta lo suben, los pagos lo bajan.
const proveedoresPorId = new Map(); // id -> proveedor, para no pasar nombres dentro de onclick
let filtroProveedor = '';

document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', () => mobileMenu.classList.toggle('hidden'));
    }

    initModalesProveedor();

    document.getElementById('search-proveedor')?.addEventListener('input', (e) => {
        filtroProveedor = e.target.value.trim().toLowerCase();
        renderProveedores();
    });

    await loadProveedores();
});

async function loadProveedores() {
    try {
        const { data, error } = await window.supabaseClient
            .from('proveedores')
            .select('*')
            .order('nombre');
        if (error) throw error;

        proveedoresPorId.clear();
        (data || []).forEach(p => proveedoresPorId.set(p.id, p));
        renderProveedores();
    } catch (error) {
        console.error('Error cargando proveedores:', error);
    }
}

function renderProveedores() {
    const tbody = document.getElementById('proveedores-table');
    if (!tbody) return;

    const todos = [...proveedoresPorId.values()];
    const visibles = todos.filter(p => {
        if (!filtroProveedor) return true;
        return [p.nombre, p.contacto, p.telefono, p.email]
            .some(v => (v || '').toLowerCase().includes(filtroProveedor));
    });

    // Resumen (sobre todos los proveedores, no solo los filtrados)
    const totalDeuda = todos.reduce((suma, p) => suma + Math.max(Number(p.saldo) || 0, 0), 0);
    document.getElementById('total-deuda').textContent = formatCurrency(totalDeuda);
    document.getElementById('total-proveedores').textContent = todos.length;

    tbody.innerHTML = '';

    if (visibles.length === 0) {
        tbody.innerHTML = `<tr><td colspan="6" class="px-6 py-8 text-center text-gray-500">${
            todos.length === 0 ? 'Todavía no cargaste proveedores' : 'No se encontraron proveedores'
        }</td></tr>`;
        return;
    }

    visibles.forEach(p => {
        const saldo = Number(p.saldo) || 0;
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">${escapeHtml(p.nombre)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${escapeHtml(p.contacto || 'N/A')}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${escapeHtml(p.telefono || 'N/A')}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${escapeHtml(p.email || 'N/A')}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-bold ${saldo > 0 ? 'text-red-600' : 'text-green-600'}">
                ${formatCurrency(saldo)}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 flex gap-3">
                <button onclick="abrirModalProveedorEdicion('${p.id}')" class="text-blue-600 hover:text-blue-800 font-medium">✏️ Editar</button>
                <button onclick="abrirModalMovProv('${p.id}')" class="text-green-600 hover:text-green-800 font-medium">💳 Saldo</button>
                <button onclick="abrirHistorialProv('${p.id}')" class="text-gray-600 hover:text-gray-900 font-medium">📜 Historial</button>
            </td>
        `;
        tbody.appendChild(row);
    });
}

// --- MODALES ---
function initModalesProveedor() {
    const modal = document.getElementById('modal-proveedor');
    const form = document.getElementById('form-proveedor');

    document.getElementById('btn-nuevo-proveedor')?.addEventListener('click', () => {
        form.reset();
        document.getElementById('prov-id-edit').value = '';
        modal.querySelector('h3').textContent = 'Nuevo Proveedor';
        modal.classList.remove('hidden');
    });

    document.getElementById('btn-cancelar-prov')?.addEventListener('click', () => modal.classList.add('hidden'));

    // Crear / editar proveedor
    form?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = form.querySelector('button[type="submit"]');
        const textoOriginal = btn.textContent;
        btn.textContent = 'Guardando...';
        btn.disabled = true;

        try {
            const id = document.getElementById('prov-id-edit').value;
            const datos = {
                nombre: document.getElementById('prov-nombre').value.trim(),
                contacto: document.getElementById('prov-contacto').value.trim() || null,
                telefono: document.getElementById('prov-telefono').value.trim() || null,
                email: document.getElementById('prov-email').value.trim() || null
            };

            // El saldo nunca se toca desde acá: solo lo cambia registrar_movimiento_proveedor
            const { error } = id
                ? await window.supabaseClient.from('proveedores').update(datos).eq('id', id)
                : await window.supabaseClient.from('proveedores').insert([datos]);
            if (error) throw error;

            modal.classList.add('hidden');
            form.reset();
            await loadProveedores();
        } catch (err) {
            console.error(err);
            alert('❌ Error: ' + err.message);
        } finally {
            btn.textContent = textoOriginal;
            btn.disabled = false;
        }
    });

    // Registrar compra a cuenta / pago
    const formMov = document.getElementById('form-mov-prov');
    formMov?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const btn = formMov.querySelector('button[type="submit"]');
        const textoOriginal = btn.textContent;
        btn.textContent = 'Procesando...';
        btn.disabled = true;

        try {
            // Una sola llamada: el servidor actualiza el saldo y guarda el movimiento en el historial
            const { data: nuevoSaldo, error } = await window.supabaseClient.rpc('registrar_movimiento_proveedor', {
                p_proveedor_id: document.getElementById('mov-prov-id').value,
                p_tipo: document.getElementById('mov-prov-tipo').value,
                p_monto: parseFloat(document.getElementById('mov-prov-monto').value),
                p_concepto: document.getElementById('mov-prov-concepto').value
            });
            if (error) throw error;

            alert(`✅ Movimiento registrado. Saldo actual: ${formatCurrency(nuevoSaldo)}`);
            cerrarModalMovProv();
            formMov.reset();
            await loadProveedores();
        } catch (err) {
            console.error(err);
            alert('❌ Error: ' + err.message);
        } finally {
            btn.textContent = textoOriginal;
            btn.disabled = false;
        }
    });
}

window.abrirModalProveedorEdicion = function(id) {
    const p = proveedoresPorId.get(id);
    if (!p) return;
    const modal = document.getElementById('modal-proveedor');
    document.getElementById('prov-id-edit').value = p.id;
    document.getElementById('prov-nombre').value = p.nombre;
    document.getElementById('prov-contacto').value = p.contacto || '';
    document.getElementById('prov-telefono').value = p.telefono || '';
    document.getElementById('prov-email').value = p.email || '';
    modal.querySelector('h3').textContent = 'Editar Proveedor';
    modal.classList.remove('hidden');
};

window.abrirModalMovProv = function(id) {
    const nombre = proveedoresPorId.get(id)?.nombre || '';
    document.getElementById('mov-prov-id').value = id;
    document.getElementById('mov-prov-nombre').textContent = `Proveedor: ${nombre}`;
    document.getElementById('form-mov-prov').reset();
    document.getElementById('modal-mov-prov').classList.remove('hidden');
};

window.cerrarModalMovProv = function() {
    document.getElementById('modal-mov-prov').classList.add('hidden');
};

// Historial de la cuenta corriente con un proveedor (tabla movimientos_proveedor).
// Las compras a cuenta suman lo que se le debe; los pagos lo restan.
window.abrirHistorialProv = async function(id) {
    const nombre = proveedoresPorId.get(id)?.nombre || '';
    document.getElementById('hist-prov-nombre').textContent = `Proveedor: ${nombre}`;
    const tbody = document.getElementById('hist-prov-body');
    tbody.innerHTML = '<tr><td colspan="5" class="px-3 py-6 text-center text-gray-500">Cargando...</td></tr>';
    document.getElementById('modal-hist-prov').classList.remove('hidden');

    const { data: movimientos, error } = await window.supabaseClient
        .from('movimientos_proveedor')
        .select('fecha, tipo, monto, concepto, created_at')
        .eq('proveedor_id', id)
        .order('created_at', { ascending: true });

    tbody.innerHTML = '';

    if (error) {
        console.error('Error cargando historial:', error);
        tbody.innerHTML = '<tr><td colspan="5" class="px-3 py-6 text-center text-red-600">No se pudo cargar el historial</td></tr>';
        return;
    }
    if (!movimientos.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="px-3 py-6 text-center text-gray-500">Este proveedor todavía no tiene movimientos</td></tr>';
        return;
    }

    const etiquetas = { compra: '📦 Compra', pago: '💰 Pago', credito: '↩️ Crédito' };

    // Saldo acumulado en orden cronológico; se muestra del más nuevo al más viejo
    let saldo = 0;
    const filas = movimientos.map(m => {
        const monto = Number(m.monto);
        const firmado = (m.tipo === 'pago' || m.tipo === 'credito') ? -monto : monto; // pago y crédito restan
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

window.cerrarHistorialProv = function() {
    document.getElementById('modal-hist-prov').classList.add('hidden');
};

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(amount || 0);
}
