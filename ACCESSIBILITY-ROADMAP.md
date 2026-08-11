# 🎯 TARIMSAL CBS – Erişilebilirlik Yol Haritası

## 📊 Tamamlanan Aşama (v1.0)

**Durum:** ✅ Beta Sürümü  
**Test:** Protanopia + Deuteranopia + Normal Vision  
**Kontrol:** CVD Mode + Tooltip'ler + Luminosity Kontrastı

| Özellik | Durum | Açıklama |
|---------|-------|----------|
| CVD Mode Toggle | ✅ Canlı | CVD-safe renk şeması, localStorage persist |
| Grid Tahmin CVD | ✅ Canlı | Turuncu → Camgöbeği (#00d4ff) |
| Dinamik Lejant | ✅ Canlı | Kategorik başlıklar + renk kombinasyonu |
| Mobil Collapse | ✅ Canlı | Lejant responsive, başlangıçta collapsed |
| Yağış Tooltip | ✅ Canlı | "Hafif/Orta/Şiddetli" metin etiketleri |
| CORINE Monokrom | ✅ Canlı | Grayscale + contrast toggle |
| Yağış Pattern | ✅ Canlı | Diagonal hatch overlay |
| MapTiler Integration | ✅ Canlı | Weather API alternatif, DEMO key |

---

## 🚀 İleri Aşama (v2.0) – Uzun Dönem

### Fase 1: MapTiler Prodüksyon (1-2 Hafta)

**Hedef:** OpenWeatherMap → MapTiler Weather API geçişi

```javascript
// Şu anda: OpenWeatherMap tiles
// Hedef: MapTiler CVD-safe radar tiles

// Yapılacak:
1. MapTiler API key endpoint konfigürasyonu
2. Fallback logic (MapTiler down → OpenWeatherMap)
3. Cache strategy (10k req/ay limit)
4. User feedback loop (CVD tester panel)
```

**Tavsiye:**
- MapTiler Free tier: 10k req/ay (~5 çalışan)
- Ücretli: $10/ay (100k req)
- Test: `DEMO_KEY_FOR_TESTING` ile başla

**Kontrol Listesi:**
- [ ] MapTiler API key konfigürasyonu
- [ ] Fallback logic test
- [ ] Cache header'ları kontrol et
- [ ] Performance benchmark (tile yükleme hızı)
- [ ] User acceptance test (CVD testerler)

---

### Fase 2: CORINE & Uydu Haritaları (2-3 Hafta)

#### A. CORINE Palette Optimizasyonu

**Hedef:** GeoVille WMS → Custom styled layer

```javascript
// Şu anda: GeoVille WMS (kontrolsüz palette)
// Hedef: Kendi renklendirilmiş CORINE WMS veya GeoTIFF

// Alternatifler:
1. GeoVille SLD (Styled Layer Descriptor) override
   - Seçenekler: Basit HTTP POST
   - Risk: WMS sunucusu SLD desteklemeyebilir

2. Copernicus Open Access Hub + tiling
   - Kaynak: https://scihub.copernicus.eu/
   - Seçenek: Cloud-optimized GeoTIFF → pmtiles/COG
   - Fiyat: Ücretsiz veri, hosting gerekli

3. Sentinel Hub → Custom vizüalizasyon
   - Seçenek: Python/JavaScript API
   - Fiyat: Free tier (limited), ücretli ($10/ay+)
   - Avantaj: 100% colorblind-safe palette kontrol
```

**Tavsiye:** Sentinel Hub (Phase 3'e ert)

#### B. NDVI & Bitki İndeksleri

**Şu anda:** NASA GIBS MODIS/Sentinel-2  
**Hedef:** Interactive Sentinel Hub custom vizüalizasyonu

```python
# Örnek: Sentinel Hub Python API
from sentinelhub import SentinelHubRequest, DataCollection, band_math

script = """
function setup() {
  return {
    input: ["B4", "B8"],
    output: {bands: 1, sampleType: "FLOAT32"}
  };
}
function evaluatePixel(pixel) {
  var ndvi = (pixel.B8 - pixel.B4) / (pixel.B8 + pixel.B4);
  return [ndvi];
}
"""
# Colorblind-safe renkli: Green-to-Brown → Blue-to-Orange
```

---

### Fase 3: Premium Sentinel Hub Entegrasyonu (1 Ay+)

**Hedef:** 100% Custom Colorblind-Safe Uydu Haritaları

**Kapasite:**
- Custom NDVI/EVI/LAI renk schemi
- Real-time Sentinel-2/1 görüntüleri
- Adaptive visualization (zoom level → data accuracy)
- Advanced analytics (ML classification)

**Maliyet:**
- Sentinel Hub: $10/ay (free tier limited)
- Hosting: $10/ay (Vercel/Netlify)
- Toplam: ~$20/ay (1 istasyonluk)

**Kontrol Listesi:**
- [ ] Sentinel Hub API keyi al
- [ ] Authentication flow kurulumu
- [ ] Custom processing script geliştir
- [ ] Colorblind palette tanımla
- [ ] Performance optimization (tile size, zoom levels)
- [ ] Integration test (harita bağlantı)

---

## 🔬 Kullanıcı Testi & Geri Bildirim

### CVD Tester Panel (v1.5)

Basit HTML panel: Gerçek colorblind kullanıcılardan geri bildirim al

```html
<!-- sidebar'da toggle -->
<button onclick="openCVDFeedback()">
  ♿ CVD Tester Feedback
</button>

<!-- Modal: Sor -->
1. Hangi renkler problem?
2. Hangi katmanları rahat görmüyorsunuz?
3. Tooltip yardımcı mı?
4. Emoji + metin + renk kombinasyonu?
```

**Platform:** Google Form + Spreadsheet (ücretsiz)

---

## 📋 Teknik Borç

| İtem | Öncelik | Tahmini | Not |
|------|---------|---------|-----|
| MapTiler fallback | Yüksek | 4 saat | OpenWeatherMap timeout handling |
| CORINE styling | Orta | 6 saat | SLD override veya WMS replace |
| Pattern overlay optimization | Düşük | 2 saat | Canvas performance (<50ms) |
| Sentinel Hub PoC | Düşük | 8 saat | API key + endpoint test |
| CVD User Panel | Orta | 3 saat | Feedback collection |
| Accessibility audit | Orta | 2 saat | WCAG 2.1 AA formal check |

---

## 💰 Bütçe Tahmini

| Kalem | Maliyeti | Dönem | Not |
|------|---------|--------|-----|
| **MapTiler API** | $0-10 | Aylık | 10k-100k req |
| **Sentinel Hub** | $0-10 | Aylık | Free-Premium tier |
| **Hosting CDN** | $0-10 | Aylık | Vercel/Netlify |
| **Developer Saati** | 40-60 saat | 2 ay | v2.0 full impl. |
| **Toplam Yıllık** | ~$240-360 | - | Scale: 5+ operator |

---

## 🎯 Sonraki Adımlar (İlk Hafta)

1. **Yarın:** MapTiler free key al → test et
2. **Pazartesi:** User feedback form aç (Google Form)
3. **Salı:** CORINE SLD styling dokümantasyonu oku
4. **Çarşamba:** Sentinel Hub API PoC (Python notebook)
5. **Cuma:** Review + roadmap refinement

---

## 📞 İletişim & Yardım

- **Geri Bildirim:** umitalgan.061@gmail.com
- **MapTiler Destek:** https://support.maptiler.com/
- **Sentinel Hub Docs:** https://docs.sentinel-hub.com/
- **Copernicus Access:** https://scihub.copernicus.eu/

**Durum:** Aktif geliştirme | **Target Release:** 2026-08-15
