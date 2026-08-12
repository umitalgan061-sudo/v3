/**
 * MapTiler Weather API Integration (CVD-Safe Radar Alternative)
 * Ankara Tarımsal CBS Platformu
 *
 * Colorblind-friendly yağış radarı kaynağı
 * API: https://maptiler.com/cloud/api/ (Ücretsiz tier: 10k req/ay)
 */

if (!window.__tarimsalMapTilerIntegrationLoaded) {
  window.__tarimsalMapTilerIntegrationLoaded = true;

let mapTilerRadarActive = false;
let mapTilerRadarLayer = null;

/**
 * MapTiler API anahtarı (opsiyonel)
 * Yapılandırma: config/api_keys.json veya doğrudan buraya
 */
const MAPTILER_API_KEY = localStorage.getItem('maptiler_key') || 'DEMO_KEY_FOR_TESTING';

/**
 * MapTiler Weather Tile Layer (CVD-safe palette)
 * Kaynak: https://docs.maptiler.com/cloud/api/weather-layers/
 *
 * Seçenekler:
 * - precipitation: Yağış (blue→cyan→green→yellow→orange→red)
 * - temperature: Sıcaklık (blue→white→red)
 * - wind_speed: Rüzgar (white→yellow→red)
 */
function makeMapTilerRadarLayer() {
  // MapTiler Weather API endpoint
  const url = `https://api.maptiler.com/maps/hybrid/tiles/xyz/{z}/{x}/{y}.png?key=${MAPTILER_API_KEY}`;

  // Alternatif: MapTiler Weather Layers (XYZ tiles)
  // https://api.maptiler.com/tiles/precipitation-1h/{z}/{x}/{y}.png?key=API_KEY

  return L.tileLayer(
    `https://api.maptiler.com/tiles/precipitation-1h/{z}/{x}/{y}.png?key=${MAPTILER_API_KEY}`,
    {
      attribution: 'MapTiler Weather Data © OpenWeatherMap',
      maxNativeZoom: 12,
      maxZoom: 19,
      opacity: 0.75,
      crossOrigin: 'anonymous',
      errorTileUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACw='
    }
  );
}

/**
 * MapTiler Radar Toggle
 */
function toggleMapTilerRadar() {
  const tog = document.getElementById('tog-maptiler-radar');
  if (!tog) return;

  if (mapTilerRadarActive) {
    if (mapTilerRadarLayer) map.removeLayer(mapTilerRadarLayer);
    mapTilerRadarLayer = null;
    mapTilerRadarActive = false;
    tog.classList.remove('on');
    return;
  }

  try {
    tog.innerHTML = '<span style="font-size:9px;color:#fff">⏳</span>';
    mapTilerRadarLayer = makeMapTilerRadarLayer();
    mapTilerRadarLayer.addTo(map);
    mapTilerRadarActive = true;
    tog.classList.add('on');
    tog.innerHTML = '';
    showToast('🌧️ MapTiler Weather (CVD-safe yağış haritası) yüklendi', 'tamam');
  } catch (e) {
    console.error('MapTiler hatası:', e);
    showToast('MapTiler Weather yüklenemedi (API key kontrol edin)', 'hata');
    tog.classList.remove('on');
    tog.innerHTML = '';
  }
}

/**
 * MapTiler API Key Konfigürasyonu (Modal)
 */
function openMapTilerSettings() {
  const key = prompt('MapTiler API Key girin (https://maptiler.com/cloud/):\n\n' +
    'Ücretsiz tier: 10k req/ay\n' +
    'Veya DEMO_KEY_FOR_TESTING için test modu',
    MAPTILER_API_KEY);

  if (key !== null) {
    localStorage.setItem('maptiler_key', key);
    location.reload();
  }
}

// Export
window.toggleMapTilerRadar = toggleMapTilerRadar;
window.openMapTilerSettings = openMapTilerSettings;

console.log('✅ MapTiler Weather API modülü yüklendi');

// ── ADDITIVE WEATHER RUNTIME FIXES ──────────────────────────────────────────
// Güncel MapTiler Weather API statik bir "precipitation-1h" tileset kimliği
// sağlamıyor. Önce weather/latest.json kataloğundan yağış değişkeninin mevcut
// keyframe kimliği bulunur, sonra bu UUID standart Tiles API ile Leaflet'e verilir.
async function makeCurrentMapTilerRadarLayer() {
  if (!MAPTILER_API_KEY || MAPTILER_API_KEY === 'DEMO_KEY_FOR_TESTING') {
    throw new Error('Geçerli MapTiler API key gerekli');
  }

  const catalogResponse = await fetch(
    `https://api.maptiler.com/weather/latest.json?key=${encodeURIComponent(MAPTILER_API_KEY)}`
  );
  if (!catalogResponse.ok) {
    throw new Error(`MapTiler weather catalog HTTP ${catalogResponse.status}`);
  }

  const catalog = await catalogResponse.json();
  const precipitation = (catalog.variables || []).find(variable => {
    const weatherVariable = variable?.metadata?.weather_variable || {};
    const haystack = `${weatherVariable.variable_id || ''} ${weatherVariable.name || ''}`.toLowerCase();
    return haystack.includes('precip');
  });
  if (!precipitation?.keyframes?.length) {
    throw new Error('MapTiler yağış keyframe verisi bulunamadı');
  }

  const now = Date.now();
  const frame = precipitation.keyframes.reduce((best, candidate) => {
    const candidateTime = Date.parse(candidate.timestamp);
    const bestTime = Date.parse(best.timestamp);
    return Math.abs(candidateTime - now) < Math.abs(bestTime - now) ? candidate : best;
  });

  return L.tileLayer(
    `https://api.maptiler.com/tiles/${encodeURIComponent(frame.id)}/{z}/{x}/{y}?key=${encodeURIComponent(MAPTILER_API_KEY)}`,
    {
      attribution: precipitation?.metadata?.weather_variable?.attribution || 'MapTiler Weather',
      maxZoom: 19,
      opacity: 0.75,
      crossOrigin: 'anonymous',
      errorTileUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACw='
    }
  );
}

async function toggleCurrentMapTilerRadar() {
  const tog = document.getElementById('tog-maptiler-radar');
  if (!tog) return;

  if (mapTilerRadarActive) {
    if (mapTilerRadarLayer) map.removeLayer(mapTilerRadarLayer);
    mapTilerRadarLayer = null;
    mapTilerRadarActive = false;
    tog.classList.remove('on');
    return;
  }

  try {
    tog.innerHTML = '<span style="font-size:9px;color:#fff">⏳</span>';
    mapTilerRadarLayer = await makeCurrentMapTilerRadarLayer();
    mapTilerRadarLayer.addTo(map);
    mapTilerRadarActive = true;
    tog.classList.add('on');
    tog.innerHTML = '';
    showToast('🌧️ MapTiler Weather yağış haritası yüklendi', 'tamam');
  } catch (e) {
    console.error('MapTiler hatası:', e);
    showToast('MapTiler Weather yüklenemedi (API key / servis kontrol edin)', 'hata');
    tog.classList.remove('on');
    tog.innerHTML = '';
  }
}

// Eski fonksiyonlar kaynakta korunur; yalnızca dışarı açılan çağrı güncel API
// akışına yönlendirilir.
window.toggleMapTilerRadar = toggleCurrentMapTilerRadar;

// Hava karşılaştırmasındaki doğrulanmış ilçe-merkezi sapmalarını mevcut
// ILCE_LOCS nesnesini silmeden, sayfa yüklenince yalnızca ilgili anahtarları düzelt.
window.addEventListener('load', () => {
  if (typeof ILCE_LOCS !== 'undefined') {
    Object.assign(ILCE_LOCS, {
      'Mamak': [39.93175, 32.91087],
      'Ayaş': [40.01942, 32.33220],
      'Evren': [39.02023, 33.80579],
      'Polatlı': [39.58333, 32.13333],
      'Haymana': [39.43414, 32.49879],
      'Nallıhan': [40.18887, 31.35061],
      'Çamlıdere': [40.49162, 32.47653]
    });
  }
});
}
