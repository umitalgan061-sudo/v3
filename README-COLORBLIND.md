# 🎨 TARIMSAL CBS – Colorblind Erişilebilirlik Rehberi

## ♿ Colorblind Mode (CVD-Safe Renk Şeması)

Harita butonlarında **👁️ Colorblind Mode** toggle'ı var. Aktif ettiğinizde:

- **Renk Palette:** Luminosity kontrastı ↑ (red-green colorblind kullanıcılar için)
- **Grid Tahmin:** Turuncu → **Açık Camgöbeği** (25°C+)
- **Dinamik Lejant:** Kategori başlıkları + renk kombinasyonu
- **Kalıcı:** Seçiminiz localStorage'da kaydedilir

### Desteklenen CVD Türleri

| Tip | Etkinlik | Tavsiye |
|-----|----------|---------|
| **Protanopia** (Red-blind) | 1% erkekler | Grid tahmin camgöbeği ✅, tooltip ekli |
| **Deuteranopia** (Green-blind) | 1% erkekler | Benzer; NDVI kontrast kontrol edildi |
| **Tritanopia** (Blue-yellow blind) | <0.001% | Seçkin; luminosity fark yeterli |
| **Achromatopsia** (Tamamen renksiz) | <0.01% | Monokrom toggle (ileri proje) |

## 🗺️ Harita Katmanları – CVD Kontrol Durumu

| Katman | Kaynak | CVD Durumu | Not |
|--------|--------|-----------|-----|
| Grid 48H Tahmin | Open-Meteo | ✅ Güvenli | Renk + rakam + emoji |
| Yağış Radaarı | OpenWeather | ⚠️ Tooltip | Tooltip: hafif/orta/şiddetli |
| CORINE Arazi Örtüsü | GeoVille WMS | ✓ Makul | Harici WMS; luminosity net |
| NDVI Bitki İndeksi | NASA GIBS | ✅ Güvenli | Yeşil → Sarı, luminosity ↑ |
| Tarla/Orman/Çayır | Custom | ✅ Güvenli | Semboloji + renk |
| Toprak Nemi | Custom | ✅ Güvenli | Yeşil (mantıklı deşifre) |

## 🎯 CVD Mode Etkinleştirildiğinde

1. **Renk Şeması Değişir:**
   - Turuncu → Camgöbeği (açık, yüksek luminosity)
   - Sarı korunur (strong contrast)
   - Kırmızı → Açık kırmızı (ışık ↑)

2. **Metin İşaretleri Eklenir:**
   - Kartlardaki sayısal değerler altı çizili (dotted)
   - Butonlar ♿ emoji ile işaretli

3. **Tooltip'ler Aktif Olur:**
   - Yağış: "Hafif (0-2mm) / Orta (2-10mm) / Şiddetli (10+mm)"
   - Grid: Sıcaklık + ikon (☀️ ❄️)

## 📞 İleri Özellikler (Roadmap)

- [ ] **Monokrom Harita:** Tüm renkleri grayscale'e çevir
- [ ] **Pattern Overlay:** Yağış radaarında hatch patterns (hafif/orta/şiddetli)
- [ ] **MapTiler Entegrasyonu:** Kendi CVD-safe radar tiles
- [ ] **Sentinel Hub Özel Vizüalizasyon:** 100% colorblind-safe uydu haritası

## 🔬 Test Etme

1. **Coblis Simulatör (Online):** https://www.color-blindness.com/coblis-color-blindness-simulator/
   - Protanopia, Deuteranopia, Tritanopia modlarında tarayıcı ekranını test edin
   - Screenshot alıp kontrol edin

2. **Kendi Görüşünüzü Kontrol Edin:**
   - Colorblind Mode açıp kapatıp tekrar açın
   - Tarla alanlarının sınırları net görülüyor mu?
   - Grid tahmin renkleri ayrıştırılabiliyor mu?

## 📧 Geri Bildirim

Colorblind modu testiniz sonrasında:
- **İyi çalışan:** Hangi katmanları rahatça görüyorsunuz?
- **Problem:** Hangi renkler hâlâ sorunlu?

umitalgan.061@gmail.com adresine yazın — erişilebilirliği iyileştirmek için hızlı hareket ederiz.

---

**Son Güncelleme:** 2026-07-21 · **Durum:** Beta (test ve geri bildirim için açık)
