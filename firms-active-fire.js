/**
 * NASA FIRMS – Tıklanabilir Aktif Yangın Nokta Katmanı
 * Ankara Tarımsal CBS Platformu
 *
 * Mevcut "firms" WMS mozaiğinin (gibs-imerg-hls-carbon.js / index.html) YERİNE
 * değil, ONUNLA BİRLİKTE çalışır: WMS ısı-haritası görsel bağlamı verir, bu
 * katman ise her noktaya tıklanınca gerçek parlaklık/güven/FRP değerini
 * gösteren tekil işaretçileri ekler. Veri firms-proxy.ashx üzerinden gelir
 * (VIIRS Suomi-NPP + NOAA-20 + NOAA-21 birleşik, 375 m çözünürlük).
 *
 * KURULUM:
 *   <script src="firms-active-fire.js"></script>  (index.html'e, diğer
 *   modüllerle aynı yere ekleyin — maptiler-integration.js'den sonrası uygun)
 *
 *   Sol paneldeki "Uydu & Çevresel" bölümüne bir satır ekleyin:
 *   <div class="lyr-row" onclick="toggleFirmsPoints()">
 *     <div class="lyr-dot" style="background:#ff3d00"></div>
 *     <div style="flex:1">
 *       <div>🔥 Aktif Yangın Noktaları (Tıklanabilir)</div>
 *       <div style="font-size:10px;color:var(--dim)" id="firmspts-date">VIIRS – son 24 saat, gerçek nokta verisi</div>
 *     </div>
 *     <div class="lyr-tog" id="tog-firmspts"></div>
 *   </div>
 */

let firmsPointsLayer = null;
let firmsPointsActive = false;
let firmsPointsTimer = null;

// NASA'nın "Near Real-Time" yayın gecikmesi (~3 saate kadar) ile MAP_KEY
// kotasını (5000 istek/10dk, proxy zaten 15 dk önbellekliyor) dengeleyen
// bir aralık — veri sunucuda tazelenir tazelenmez istemci de yakalar.
const FIRMS_REFRESH_MS = 20 * 60 * 1000; // 20 dakika

async function fetchFirmsPoints() {
  const r = await fetch('firms-proxy.ashx');
  if (!r.ok) throw new Error('HTTP ' + r.status);
  const d = await r.json();
  if (d.ok === false) throw new Error(d.error || 'FIRMS verisi alınamadı');
  return d;
}

// FRP (Fire Radiative Power, MW) değerine göre renk — yüksek FRP daha büyük/aktif yangını gösterir
function frpColor(frp) {
  const v = parseFloat(frp);
  if (!Number.isFinite(v)) return '#ff9800';
  if (v >= 100) return '#b71c1c';
  if (v >= 50)  return '#e53935';
  if (v >= 15)  return '#ff5722';
  if (v >= 5)   return '#ff9800';
  return '#ffc107';
}

function confidenceLabel(raw) {
  // VIIRS: 'l'/'n'/'h' (low/nominal/high) harfli; bazı ürünlerde 0-100 sayısal gelir
  if (raw == null) return '—';
  const s = String(raw).toLowerCase();
  if (s === 'l') return 'Düşük';
  if (s === 'n') return 'Orta (Nominal)';
  if (s === 'h') return 'Yüksek';
  const n = parseFloat(raw);
  if (Number.isFinite(n)) return n >= 80 ? `Yüksek (${n})` : n >= 30 ? `Orta (${n})` : `Düşük (${n})`;
  return String(raw);
}

function makeFirmsPointLayer(geojson) {
  return L.geoJSON(geojson, {
    pointToLayer: (feature, latlng) => {
      const p = feature.properties || {};
      const color = frpColor(p.frp);
      return L.circleMarker(latlng, {
        radius: 6,
        color: '#fff',
        weight: 1.2,
        fillColor: color,
        fillOpacity: 0.85
      }).bindPopup(`
        <b>🔥 Aktif Yangın / Termal Anomali</b><br>
        <div class="popup-row"><span class="popup-key">Uydu</span><span class="popup-val">${escapeHtml(p.satellite || '—')}</span></div>
        <div class="popup-row"><span class="popup-key">Tarih / Saat (UTC)</span><span class="popup-val">${escapeHtml(p.acq_date || '—')} ${escapeHtml(String(p.acq_time || '').padStart(4,'0'))}</span></div>
        <div class="popup-row"><span class="popup-key">Güven Düzeyi</span><span class="popup-val">${escapeHtml(confidenceLabel(p.confidence))}</span></div>
        <div class="popup-row"><span class="popup-key">Yangın Gücü (FRP)</span><span class="popup-val">${p.frp != null ? p.frp + ' MW' : '—'}</span></div>
        <div class="popup-row"><span class="popup-key">Parlaklık Sıc. (I4/I5)</span><span class="popup-val">${p.bright_ti4 ?? '—'} K / ${p.bright_ti5 ?? '—'} K</span></div>
        <div class="popup-row"><span class="popup-key">Gündüz/Gece</span><span class="popup-val">${p.daynight === 'D' ? 'Gündüz' : p.daynight === 'N' ? 'Gece' : '—'}</span></div>
        <div style="margin-top:6px;font-size:10px;color:var(--dim)">NASA FIRMS · VIIRS 375 m · gerçek zamanlıya en yakın (NRT)</div>
      `);
    }
  });
}

async function toggleFirmsPoints() {
  const tog = document.getElementById('tog-firmspts');
  if (!tog) return;

  if (firmsPointsActive) {
    firmsPointsActive = false;
    clearInterval(firmsPointsTimer); firmsPointsTimer = null;
    if (firmsPointsLayer && map.hasLayer(firmsPointsLayer)) map.removeLayer(firmsPointsLayer);
    firmsPointsLayer = null;
    tog.classList.remove('on');
    const lbl = document.getElementById('firmspts-date');
    if (lbl) lbl.textContent = 'VIIRS – son 24 saat, gerçek nokta verisi';
    return;
  }

  tog.innerHTML = '<span style="font-size:9px;color:#fff">⏳</span>';
  try {
    const data = await fetchFirmsPoints();
    firmsPointsLayer = makeFirmsPointLayer(data);
    firmsPointsLayer.addTo(map);
    firmsPointsActive = true;
    tog.classList.add('on');
    tog.innerHTML = '';

    const lbl = document.getElementById('firmspts-date');
    if (lbl) lbl.textContent = `🔥 ${data.count} nokta · güncellendi ${new Date(data.generatedAt).toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'})}`;

    showToast(`🔥 ${data.count} aktif yangın/termal anomali noktası yüklendi (VIIRS, tıklanabilir)`, data.count > 0 ? 'tamam' : 'bilgi');

    // Periyodik tazeleme: sunucu proxy'si zaten 15 dk önbellekli, burada 20 dk'da
    // bir yeniden çekilerek yeni geçişlerdeki tazelenme yakalanır.
    firmsPointsTimer = setInterval(async () => {
      if (!firmsPointsActive) return;
      try {
        const fresh = await fetchFirmsPoints();
        if (firmsPointsLayer) map.removeLayer(firmsPointsLayer);
        firmsPointsLayer = makeFirmsPointLayer(fresh);
        firmsPointsLayer.addTo(map);
        const lbl2 = document.getElementById('firmspts-date');
        if (lbl2) lbl2.textContent = `🔥 ${fresh.count} nokta · güncellendi ${new Date(fresh.generatedAt).toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'})}`;
      } catch (e) { console.warn('FIRMS nokta verisi tazelenemedi:', e.message); }
    }, FIRMS_REFRESH_MS);
  } catch (e) {
    console.error('FIRMS nokta verisi alınamadı:', e);
    showToast('Aktif yangın nokta verisi alınamadı (firms-proxy.ashx / MAP_KEY kontrol edin).', 'hata');
    tog.classList.remove('on');
    tog.innerHTML = '';
  }
}

window.toggleFirmsPoints = toggleFirmsPoints;
console.log('✅ FIRMS aktif yangın nokta modülü yüklendi');
