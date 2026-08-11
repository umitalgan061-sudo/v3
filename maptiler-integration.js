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
}
