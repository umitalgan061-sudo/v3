/**
 * MapTiler Weather API Integration (CVD-Safe Radar Alternative)
 * Ankara Tarımsal CBS Platformu
 *
 * Colorblind-friendly yağış radarı kaynağı
 * API: https://maptiler.com/cloud/api/ (Ücretsiz tier: 10k req/ay)
 */

if (!window.__tarimsalMapTilerIntegrationLoaded) {
  window.__tarimsalMapTilerIntegrationLoaded = true;

// NATIVE_PWA_INSTALL_GUARD_V1 — native Capacitor kabında uygulama zaten kurulu;
// web/PWA tarafındaki "Uygulamayı Yükle / Ana Ekrana Ekle" banner'ı gösterilmesin.
// Mevcut install akışını değiştirmeden onun kullandığı dismissal anahtarını işaretle.
try {
  if (window.Capacitor?.isNativePlatform?.() === true) {
    localStorage.setItem('abb_tarim_install_dismissed', 'native-container');
  }
} catch (_) {}

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

// Hava karşılaştırmasındaki doğrulanmış ilçe-merkezi sapmalarını mevcut
// ILCE_LOCS nesnesini veya eski değerleri silmeden, sayfa yüklenince düzelt.
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
    // Ankara'nın resmi 25-ilçe listesinde olup karşılaştırma tablosunda eksik
    // kalan ilçeleri ekle. Mevcut ILCE_LOCS tanımı ve eski değerler korunur.
    Object.assign(ILCE_LOCS, {
      'Akyurt': [40.13075, 33.08707],
      'Elmadağ': [39.92213, 33.22627],
      'Etimesgut': [39.94894, 32.66208],
      'Güdül': [40.21051, 32.24552]
    });

    // Keskin Ankara ilçesi değildir; Keceli ve Hasanoğlan da ilçe değildir.
    // Kaynak değerleri silmeden Object.entries(ILCE_LOCS) karşılaştırma listesinden
    // çıkar: özellikler doğrudan erişimde kalır, yalnızca enumerable olmaz.
    ['Keskin', 'Keceli', 'Hasanoğlan'].forEach(name => {
      if (Object.prototype.hasOwnProperty.call(ILCE_LOCS, name)) {
        Object.defineProperty(ILCE_LOCS, name, { enumerable: false });
      }
    });
  }
});
}
