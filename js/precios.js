// Variables globales
let productosCache = [];
let categoriasUnicas = new Set();

document.addEventListener('DOMContentLoaded', async () => {
    // Mobile menu toggle
    const mobileMenuBtn = document.getElementById('mobile-menu-btn');
    const mobileMenu = document.getElementById('mobile-menu');
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', () => mobileMenu.classList.toggle('hidden'));
    }

    await cargarProductos();
    initFiltros();
    initModalLogic();
});

// Cargar SOLO productos activos
async function cargarProductos() {
    try {
        const { data, error } = await window.supabaseClient
            .from('productos')
            .select('*')
            .eq('activo', true)
            .order('nombre');
        
        if (error) throw error;
        productosCache = data || [];
        
        categoriasUnicas = new Set(productosCache.map(p => p.categoria).filter(Boolean));
        actualizarSelectCategorias();
        renderizarTablaEditable(productosCache);
    } catch (err) {
        console.error('Error cargando productos:', err);
    }
}

function actualizarSelectCategorias() {
    const select = document.getElementById('filtro-categoria');
    if (!select) return;
    select.innerHTML = '<option value="">Todas las categorías</option>';
    [...categoriasUnicas].sort().forEach(cat => {
        const opt = document.createElement('option');
        opt.value = cat;
        opt.textContent = cat;
        select.appendChild(opt);
    });
}

function initFiltros() {
    const inputBusqueda = document.getElementById('filtro-producto');
    const selectCategoria = document.getElementById('filtro-categoria');
    
    const filtrar = () => {
        const texto = inputBusqueda?.value.toLowerCase() || '';
        const categoria = selectCategoria?.value || '';
        
        const filtrados = productosCache.filter(p => {
            const coincideTexto = p.nombre.toLowerCase().includes(texto);
            const coincideCat = !categoria || p.categoria === categoria;
            return coincideTexto && coincideCat;
        });
        
        renderizarTablaEditable(filtrados);
    };

    inputBusqueda?.addEventListener('input', filtrar);
    selectCategoria?.addEventListener('change', filtrar);
}

function renderizarTablaEditable(productos) {
    const tbody = document.getElementById('tabla-precios-body');
    if (!tbody) return;
    
    tbody.innerHTML = '';
    
    if (productos.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="px-6 py-8 text-center text-gray-500">No se encontraron productos activos</td></tr>';
        return;
    }

    productos.forEach(p => {
        const tr = document.createElement('tr');
        tr.className = 'hover:bg-gray-50 transition-colors';
        
        const celdasPrecios = [
            { nombre: 'precio_minorista', label: 'Minorista', color: 'green' },
            { nombre: 'precio_mayorista', label: 'Mayorista', color: 'blue' },
            { nombre: 'precio_distribuidor', label: 'Distribuidor', color: 'purple' }
        ];

        let htmlCeldas = `
            <td class="px-4 py-3 whitespace-nowrap text-sm font-medium text-gray-900 min-w-[150px]">${p.nombre}</td>
            <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-600">${formatCurrency(p.costo)}</td>
        `;

        celdasPrecios.forEach(celda => {
            const precio = p[celda.nombre];
            const margen = calcularMargen(p.costo, precio);
            const badge = margen ? `<span class="block text-[10px] mt-1 ${margen.clase}">↗ ${margen.valor}%</span>` : '';
            
            htmlCeldas += `
                <td class="px-4 py-3 whitespace-nowrap">
                    <div class="relative">
                        <input type="number" step="0.01" 
                               value="${precio ?? ''}" 
                               data-id="${p.id}"
                               data-campo="${celda.nombre}"
                               class="w-full border border-gray-300 rounded px-3 py-2 text-sm text-${celda.color}-700 font-semibold 
                                      focus:ring-2 focus:ring-${celda.color}-500 focus:border-${celda.color}-500 outline-none 
                                      transition-all hover:border-${celda.color}-400 min-h-[44px]"
                               placeholder="0.00"
                               onblur="guardarPrecioInline(this)"
                               onkeydown="if(event.key==='Enter'){this.blur(); event.preventDefault();}">
                        ${badge}
                    </div>
                </td>
            `;
        });

        // Columna de Acciones (Activar/Desactivar + Eliminar)
        htmlCeldas += `
            <td class="px-4 py-3 whitespace-nowrap text-right">
                <div class="flex gap-2 justify-end">
                    <button onclick="toggleProductoActivo('${p.id}', '${p.nombre.replace(/'/g, "\\'")}', true)" 
                            class="text-xs font-medium px-3 py-1 rounded border border-yellow-300 text-yellow-700 hover:bg-yellow-50 transition-colors min-h-[36px]">
                        ⏸ Desactivar
                    </button>
                    <button onclick="eliminarProductoDefinitivo('${p.id}', '${p.nombre.replace(/'/g, "\\'")}')" 
                            class="text-xs font-medium px-3 py-1 rounded border border-red-200 text-red-600 hover:bg-red-50 transition-colors min-h-[36px]"
                            title="Eliminación permanente">
                        🗑️
                    </button>
                </div>
            </td>
        `;

        tr.innerHTML = htmlCeldas;
        tbody.appendChild(tr);
    });
}

// Guardar precio al perder foco o Enter
window.guardarPrecioInline = async function(input) {
    const id = input.dataset.id;
    const campo = input.dataset.campo;
    const valor = parseFloat(input.value);
    
    if (isNaN(valor) || valor < 0) {
        input.classList.add('border-red-500', 'ring-2', 'ring-red-200');
        setTimeout(() => input.classList.remove('border-red-500', 'ring-2', 'ring-red-200'), 1500);
        return;
    }

    const originalBg = input.style.backgroundColor;
    input.style.backgroundColor = '#dcfce7';
    
    try {
        const { error } = await window.supabaseClient
            .from('productos')
            .update({ [campo]: valor })
            .eq('id', id);
            
        if (error) throw error;
        
        const prod = productosCache.find(p => p.id === id);
        if (prod) {
            prod[campo] = valor;
            // Re-renderizar para actualizar badges de margen
            const filtroTexto = document.getElementById('filtro-producto')?.value.toLowerCase() || '';
            const filtroCat = document.getElementById('filtro-categoria')?.value || '';
            const filtrados = productosCache.filter(p => {
                const coincideTexto = p.nombre.toLowerCase().includes(filtroTexto);
                const coincideCat = !filtroCat || p.categoria === filtroCat;
                return coincideTexto && coincideCat;
            });
            renderizarTablaEditable(filtrados);
        }
        
    } catch (err) {
        console.error('Error guardando precio:', err);
        input.style.backgroundColor = '#fee2e2';
        alert('Error al guardar: ' + err.message);
    } finally {
        setTimeout(() => { input.style.backgroundColor = originalBg; }, 800);
    }
};

// Activar / Desactivar producto
window.toggleProductoActivo = async function(id, nombre, estadoActual) {
    const nuevoEstado = !estadoActual;
    
    if (!nuevoEstado && !confirm(`¿Desactivar "${nombre}"?\nNo aparecerá en nuevas ventas ni en esta lista.`)) return;

    try {
        const { error } = await window.supabaseClient
            .from('productos')
            .update({ activo: nuevoEstado })
            .eq('id', id);

        if (error) throw error;

        if (nuevoEstado) {
            await cargarProductos(); // Recargar desde DB
        } else {
            productosCache = productosCache.filter(p => p.id !== id);
            renderizarTablaEditable(productosCache);
        }
        
    } catch (err) {
        console.error(err);
        alert('❌ Error: ' + err.message);
    }
};

// Eliminación definitiva (con manejo de FK)
window.eliminarProductoDefinitivo = async function(id, nombre) {
    if (!confirm(`⚠️ ELIMINACIÓN PERMANENTE\n¿Borrar "${nombre}" para siempre?\nEsto no se puede deshacer.`)) return;

    try {
        const { error } = await window.supabaseClient
            .from('productos')
            .delete()
            .eq('id', id);

        if (error) {
            if (error.code === '23503') {
                alert(' No se puede eliminar porque tiene historial de ventas.\nUsa "Desactivar" en su lugar.');
                return;
            }
            throw error;
        }

        productosCache = productosCache.filter(p => p.id !== id);
        renderizarTablaEditable(productosCache);
        alert('✅ Producto eliminado permanentemente');
        
    } catch (err) {
        console.error(err);
        alert(' Error: ' + err.message);
    }
};

function calcularMargen(costo, precio) {
    if (!costo || !precio || costo <= 0) return null;
    const margen = ((precio - costo) / costo * 100).toFixed(1);
    let clase = 'text-red-600';
    if (margen >= 30) clase = 'text-green-600 font-bold';
    else if (margen >= 15) clase = 'text-yellow-600';
    return { valor: margen, clase };
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(amount || 0);
}

// --- LÓGICA DEL MODAL DE CREACIÓN ---
function initModalLogic() {
    const modal = document.getElementById('modal-producto');
    const btnNuevo = document.getElementById('btn-nuevo-producto');
    const btnCancelar = document.getElementById('btn-cancelar');
    const formProducto = document.getElementById('form-producto');

    if (btnNuevo && modal) {
        btnNuevo.addEventListener('click', () => {
            formProducto.reset();
            modal.classList.remove('hidden');
            setTimeout(() => document.getElementById('prod-nombre')?.focus(), 100);
        });
    }

    if (btnCancelar && modal) {
        btnCancelar.addEventListener('click', () => {
            modal.classList.add('hidden');
            formProducto.reset();
        });
    }

    if (modal) {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.classList.add('hidden');
                formProducto.reset();
            }
        });
    }

    if (formProducto) {
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
                    precio_distribuidor: parseFloat(document.getElementById('prod-p-distribuidor').value) || null,
                    activo: true // Nuevo producto siempre activo
                };

                const { error } = await window.supabaseClient.from('productos').insert([nuevoProducto]);
                if (error) throw error;

                modal.classList.add('hidden');
                formProducto.reset();
                await cargarProductos();
                
            } catch (err) {
                console.error(err);
                alert('❌ Error al guardar: ' + err.message);
            } finally {
                btnSubmit.textContent = originalText;
                btnSubmit.disabled = false;
            }
        });
    }
}
