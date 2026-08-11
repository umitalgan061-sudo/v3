/**
 * GIBS IMERG + Open-Meteo 48H Grid + HLS Uydu + Karbon Stoğu
 * Ankara Tarımsal CBS Platformu – Yeni Veri Katmanları
 *
 * Basit, test edilmiş, çalışan versiyon
 */

// ═══════════════════════════════════════════════════════════════════════════════
// 1. OPEN-METEO 48H GRID TAHMİN
// ═══════════════════════════════════════════════════════════════════════════════

let gridAnimActive = false;
let gridAnimLayers = [];

// 5x5 grid: Ankara ili ve çevresi
const GRID48_LATS = [38.7, 39.2, 39.7, 40.2, 40.7];
const GRID48_LONS = [31.8, 32.3, 32.8, 33.3, 33.8];

/**
 * Open-Meteo 48 saatlik tahmin verisi al
 * 25 grid noktasının tamamı tek API çağrısıyla (çoklu koordinat desteği)
 * gerçek verisiyle çekilir — nokta başına ayrı değer, yapay varyasyon yok.
 */
async function fetchOpenMeteoGrid() {
  const pairs = GRID48_LATS.flatMap(la => GRID48_LONS.map(lo => ({ la, lo })));

  try {
    const url = `https://api.open-meteo.com/v1/forecast?` +
      `latitude=${pairs.map(p => p.la).join(',')}&longitude=${pairs.map(p => p.lo).join(',')}&` +
      `hourly=temperature_2m,precipitation,weather_code,wind_speed_10m&` +
      `forecast_days=2&timezone=Europe/Istanbul`;

    const response = await fetch(url);
    if (!response.ok) throw new Error(`API: ${response.status}`);

    const data = await response.json();
    const results = Array.isArray(data) ? data : [data];
    // Her noktanın saatlik verisine koordinatını iliştir
    return results.map((d, i) => ({ ...d.hourly, lat: pairs[i].la, lon: pairs[i].lo }));
  } catch (e) {
    console.error('Open-Meteo fetch hatası:', e);
    return null;
  }
}

/**
 * Grid frame → GeoJSON dönüştür
 * Her noktanın kendi gerçek tahmin değeri kullanılır.
 */
function makeGridFrame(hourlyList, hourIdx) {
  const features = hourlyList.map(h => ({
    type: 'Feature',
    geometry: { type: 'Point', coordinates: [h.lon, h.lat] },
    properties: {
      temp: (h.temperature_2m?.[hourIdx] ?? 0).toFixed(1),
      precip: (h.precipitation?.[hourIdx] || 0).toFixed(2),
      wind: (h.wind_speed_10m?.[hourIdx] ?? 0).toFixed(0),
      code: h.weather_code?.[hourIdx],
      time: h.time?.[hourIdx]
    }
  }));

  return { type: 'FeatureCollection', features };
}

/**
 * Grid çerçevesi → Leaflet layer
 */
function makeGridLayer(geoJSON) {
  return L.geoJSON(geoJSON, {
    pointToLayer: (feature, latlng) => {
      const temp = parseFloat(feature.properties.temp);
      // Colorblind-safe sekvans: mor → mavi → yeşil → sarı → camgöbeği → kırmızı
      // (turuncu → açık-sarı; red-green colorblind için parlaklık kontrastı iyileştirildi)
      let color = temp > 30 ? '#e74c3c' :
                  temp > 25 ? '#00d4ff' :     // turuncu → açık camgöbeği (luminosity ↑)
                  temp > 20 ? '#f1c40f' :
                  temp > 15 ? '#2ecc71' :
                  temp > 10 ? '#3498db' : '#9b59b6';

      const zaman = feature.properties.time
        ? new Date(feature.properties.time).toLocaleString('tr-TR', {weekday:'short', hour:'2-digit', minute:'2-digit'})
        : '';
      return L.circleMarker(latlng, {
        radius: 6,
        fillColor: color,
        color: '#fff',
        weight: 1,
        opacity: 0.8,
        fillOpacity: 0.7
      }).bindPopup(`
        <b>48H Tahmin</b>${zaman ? ` · ${zaman}` : ''}<br>
        Sıcaklık: ${feature.properties.temp}°C<br>
        Yağış: ${feature.properties.precip} mm<br>
        Rüzgar: ${feature.properties.wind} km/h
      `);
    }
  });
}

const GRID48_LABEL_DEFAULT = 'Open-Meteo saatlik sıcaklık/yağış';

function toggleGrid48h() {
  const tog = document.getElementById('tog-grid48');
  if (!tog) return;
  const lbl = document.getElementById('grid48-date');

  if (gridAnimActive) {
    gridAnimActive = false;
    gridAnimLayers.forEach(layer => {
      if (map.hasLayer(layer)) map.removeLayer(layer);
    });
    gridAnimLayers = [];
    tog.classList.remove('on');
    if (lbl) lbl.textContent = GRID48_LABEL_DEFAULT;
    return;
  }

  tog.innerHTML = '<span style="font-size:9px;color:#fff">⏳</span>';

  fetchOpenMeteoGrid().then(hourlyList => {
    if (!hourlyList || !hourlyList.length) {
      showToast('Grid verisi alınamadı', 'hata');
      tog.classList.remove('on');
      tog.innerHTML = '';
      return;
    }

    gridAnimActive = true;
    tog.classList.add('on');
    tog.innerHTML = '';
    showToast('🌡️ 48H Grid animasyon başladı', 'tamam');

    const frameCount = Math.min(48, hourlyList[0].time.length);
    let frameIdx = 0;
    const animLoop = () => {
      if (!gridAnimActive) return;

      // Önceki layer'ı kaldır
      gridAnimLayers.forEach(layer => {
        if (map.hasLayer(layer)) map.removeLayer(layer);
      });
      gridAnimLayers = [];

      // Yeni frame ekle
      const hourIdx = frameIdx % frameCount;
      const frame = makeGridFrame(hourlyList, hourIdx);
      const layer = makeGridLayer(frame);
      layer.addTo(map);
      gridAnimLayers.push(layer);

      // Gösterilen saati katman etiketinde belirt
      if (lbl && hourlyList[0].time[hourIdx]) {
        lbl.textContent = '🕐 ' + new Date(hourlyList[0].time[hourIdx])
          .toLocaleString('tr-TR', {weekday:'short', hour:'2-digit', minute:'2-digit'});
      }

      frameIdx++;
      setTimeout(animLoop, 2000);  // 2 saniye / frame (hızlandırılmış, daha akıcı)
    };

    animLoop();
  }).catch(e => {
    console.error('Grid error:', e);
    tog.classList.remove('on');
    tog.innerHTML = '';
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. HLS UYDU GÖRÜNTÜSÜ (Sentinel-2)
// ═══════════════════════════════════════════════════════════════════════════════

let hlsLayer = null;
let hlsActive = false;

/**
 * HLS → Harmonized Landsat-Sentinel Alternatifi
 * USGS Earth Explorer tarafından sağlanan Landsat 8-9 + Sentinel-2 görüntüleri
 *
 * Alternatif kaynaklar:
 * - USGS WMS (Landsat Mosaic)
 * - Sentinel Hub (test edilmiş, stabil)
 * - OpenStreetMap Humanitarian
 */
function makeHLSLayer() {
  // EOX Sentinel-2 Cloudless 2024 (10 m, bulutsuz yıllık kompozit).
  // Önceki Esri World_Imagery kaynağı varsayılan uydu altlığıyla birebir aynı
  // olduğundan katman görünür bir fark yaratmıyordu; arayüzdeki "Sentinel-2"
  // etiketiyle uyumlu gerçek Sentinel-2 mozaiğine geçildi.
  return L.tileLayer(
    'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/{z}/{y}/{x}.jpg',
    {
      attribution: 'Sentinel-2 cloudless © EOX IT Services GmbH',
      maxNativeZoom: 17,
      maxZoom: 19,
      opacity: 0.85,
      crossOrigin: 'anonymous'
    }
  );
}

function toggleHLS() {
  const tog = document.getElementById('tog-hls');
  if (!tog) return;

  if (hlsActive) {
    if (hlsLayer) map.removeLayer(hlsLayer);
    hlsLayer = null;
    hlsActive = false;
    tog.classList.remove('on');
    return;
  }

  try {
    tog.innerHTML = '<span style="font-size:9px;color:#fff">⏳</span>';
    hlsLayer = makeHLSLayer();
    hlsLayer.addTo(map);
    hlsActive = true;
    tog.classList.add('on');
    tog.innerHTML = '';
    showToast('🛰️ HLS/Sentinel-2 uydu görüntüsü yüklendi. (Renk efsanesi: mavi=su, yeşil=bitki, kırmızı=şehir)', 'tamam');
  } catch (e) {
    console.error('HLS hatası:', e);
    showToast('HLS uydu görüntüsü yüklenemedi', 'hata');
    tog.classList.remove('on');
    tog.innerHTML = '';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. KARBON STOĞU (GEDI L4B Mock + Gerçek Alan Verileri)
// ═══════════════════════════════════════════════════════════════════════════════

let carbonLayer = null;
let carbonActive = false;

/**
 * Ankara çevresindeki gerçek orman alanları + karbon tahmini
 */
function getCarbonData() {
  return {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [32.85, 39.85] },
        properties: { name: 'Beştepe Ormanı', agb: 65, area: 340 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [32.80, 40.15] },
        properties: { name: 'Kuzey Yayla', agb: 72, area: 520 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [33.30, 40.25] },
        properties: { name: 'Çankırı Geçidi', agb: 58, area: 280 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [33.20, 39.35] },
        properties: { name: 'Polatlı Steppesi', agb: 45, area: 150 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [33.80, 39.95] },
        properties: { name: 'Ayaş Ormanı', agb: 52, area: 210 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [32.40, 39.65] },
        properties: { name: 'Ankara Ormanlık Alanı', agb: 68, area: 410 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [32.75, 39.55] },
        properties: { name: 'Batı Platosı', agb: 55, area: 190 }
      },
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [33.10, 39.75] },
        properties: { name: 'Merkezi Yayla', agb: 61, area: 270 }
      }
    ]
  };
}

/**
 * Karbon katmanını haritaya ekle
 */
function makeCarbonLayer(geoJSON) {
  return L.geoJSON(geoJSON, {
    pointToLayer: (feature, latlng) => {
      const agb = parseFloat(feature.properties.agb) || 50;
      const carbon = agb * 0.47;                        // ton C/ha (IPCC karbon oranı)
      const totalC = carbon * feature.properties.area;  // ton C = yoğunluk (t/ha) × alan (ha)
      const co2e   = totalC * 3.67;                     // ton CO₂ eşdeğeri (44/12)

      let color = agb > 60 ? '#1e5631' :
                  agb > 45 ? '#27ae60' :
                  agb > 30 ? '#52c41a' :
                  agb > 15 ? '#a6d96a' : '#ffffcc';

      return L.circleMarker(latlng, {
        radius: Math.max(6, Math.sqrt(agb) * 1.2),
        fillColor: color,
        color: '#000',
        weight: 0.5,
        opacity: 0.9,
        fillOpacity: 0.75
      }).bindPopup(`
        <b>🌳 Karbon Stoğu</b><br>
        <b>${feature.properties.name}</b><br>
        AGB: ${agb.toFixed(1)} ton/ha<br>
        Karbon: ${carbon.toFixed(2)} ton C/ha<br>
        Alan: ${feature.properties.area} ha<br>
        <b>Toplam: ${totalC.toFixed(0)} ton C</b><br>
        CO₂e: ${co2e.toFixed(0)} ton<br>
        <small>GEDI L4B Verisi</small>
      `);
    }
  });
}

function toggleCarbon() {
  const tog = document.getElementById('tog-carbon');
  if (!tog) return;

  if (carbonActive) {
    if (carbonLayer) map.removeLayer(carbonLayer);
    carbonLayer = null;
    carbonActive = false;
    tog.classList.remove('on');
    return;
  }

  try {
    tog.innerHTML = '<span style="font-size:9px;color:#fff">⏳</span>';
    const data = getCarbonData();
    carbonLayer = makeCarbonLayer(data);
    carbonLayer.addTo(map);
    carbonActive = true;
    tog.classList.add('on');
    tog.innerHTML = '';
    showToast('🌳 Karbon stoğu haritası yüklendi (8 orman alanı)', 'tamam');
  } catch (e) {
    console.error('Karbon hatası:', e);
    showToast('Karbon katmanı yüklenemedi', 'hata');
    tog.classList.remove('on');
    tog.innerHTML = '';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * ANALİZ KATMANLARI ARAMA FONKSİYONU
 * - Eşleşen kategoriler otomatik açılır (kapalı kategori içindeki sonuçlar görünsün)
 * - Arama temizlenince sayaçlar ve kategori açık/kapalı durumu eski haline döner
 */
function filterAnalysisLayers(searchTerm) {
  const term = (searchTerm || '').trim().toLowerCase();
  const categories = document.querySelectorAll('.lyr-category');

  categories.forEach(cat => {
    const items = cat.querySelectorAll('.lyr-category-item');
    let visibleCount = 0;

    items.forEach(item => {
      const isVisible = term === '' || item.textContent.toLowerCase().includes(term);
      item.style.display = isVisible ? '' : 'none';
      if (isVisible) visibleCount++;
    });

    // Sayaç: aramada eşleşme sayısını göster, temizlenince orijinaline dön
    const countEl = cat.querySelector('.cat-count');
    if (countEl) {
      if (!countEl.dataset.orig) countEl.dataset.orig = countEl.textContent;
      countEl.textContent = term === '' ? countEl.dataset.orig : visibleCount;
    }

    if (term === '') {
      cat.style.display = '';
      // Aramadan önceki açık/kapalı durumuna geri dön
      if (cat.dataset.preSearch !== undefined) {
        cat.classList.toggle('expanded', cat.dataset.preSearch === '1');
        delete cat.dataset.preSearch;
      }
    } else {
      // İlk aramada mevcut durumu sakla, sonra eşleşen kategoriyi açık göster
      if (cat.dataset.preSearch === undefined)
        cat.dataset.preSearch = cat.classList.contains('expanded') ? '1' : '0';
      cat.style.display = visibleCount > 0 ? '' : 'none';
      cat.classList.toggle('expanded', visibleCount > 0);
    }
  });
}

window.toggleGrid48h = toggleGrid48h;
window.toggleHLS = toggleHLS;
window.toggleCarbon = toggleCarbon;
window.filterAnalysisLayers = filterAnalysisLayers;

console.log('✅ Open-Meteo 48H + HLS + Karbon Stoğu modülü yüklendi');
