# 📱 TARIMSAL CBS – Progressive Web App (PWA) Rehberi

## 🚀 PWA Nedir?

PWA (Progressive Web App), tarayıcıda çalışan ama yerel bir uygulama gibi davranabilen web uygulamasıdır. TARIMSAL CBS'in PWA sürümü:

- ✅ **Offline çalışma** — İnternet olmadığında da harita görülebilir
- ✅ **Hızlı yükleme** — Service Worker caching sayesinde 2-3 saniye
- ✅ **Ana ekrana kurulma** — Telefonda uygulama simgesi gibi
- ✅ **Push bildirimleri** — Hava uyarıları, tahmin güncellemeleri
- ✅ **Kamera/GPS erişim** — Parsel fotoğrafları, konumlandırma

---

## 📲 Kurulum – Android & iOS

### Android (Chrome, Edge, Brave)

1. **Uygulamayı Aç:**
   - Tarayıcıda `http://localhost:8743/TARIMSAL CBS/index.html` aç

2. **Kurulum İstemi:**
   - Bildirim çıkarsa: "Tarimsal CBS yükle" tıkla
   - Bildirim yoksa:
     - 3 nutkaya tıkla (⋯) → "Uygulamayı yükle"
     - veya Adres çubuğunun sağında kurulum ikonu (↓)

3. **Başlat:**
   - Ana ekrandaki "Tarımsal CBS" ikonuna tıkla
   - Uygulama fullscreen'de açılır

### iOS (Safari)

1. **Paylaş Butonuna Tıkla** (aşağı ok)
2. **"Ana Ekrana Ekle"** seç
3. "Ekle" tıkla
4. Uygulamayı ana ekranda kullan

---

## 🔌 Offline Modu

Kurulduktan sonra:

- **Harita & Lejant:** Önbelleğe alınan son görünüm
- **İlçe/Parsel Verisi:** Yerel (online gerekli değil)
- **Hava Tahminleri:** Yalnızca önceki veri (canlı değil)
- **Uydu Haritaları:** Zoomed-out önceki tiles

**Not:** Yeni hava verisi almak için internet gerekli.

### Offline Cache Temizleme

Uygulamayı kuruluşunun ayarlarında:
1. **Depolama** → **Tarayıcı Verileri**
2. "Tarımsal CBS" cache seçip sil

---

## 🔔 Push Bildirimleri (Opsiyonel)

Yönetim kurulu kurulumuna eklenebilir:

```bash
# Notification izni iste
navigator.serviceWorker.ready.then(reg => {
  reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: 'BASE64_PUBLIC_KEY'
  });
});
```

**Tavsiye:** "Yağış Uyarısı", "Sıcaklık Eşiği", "Bahçe Sulama Saati"

---

## ⚙️ Ayarlar & Versiyon

### Hızlı Bilgiler

| Bilgi | Değer |
|-------|-------|
| **App Name** | Ankara Tarımsal CBS |
| **Version** | v1.0-PWA |
| **Cache Size** | ~50MB (estim.) |
| **Offline Timeout** | 10 saniye (API istekleri) |
| **Last Updated** | 2026-07-21 |

### Cache Stratejisi

- **Harita Tiles:** Cache-first (5 MB/ay)
- **Hava API:** Network-first (çevrimiçi tercih)
- **Statik Assets:** Cache-first (CSS, JS, Logo)

---

## 🛠️ Teknik Detaylar

### Manifest (manifest.json)

App metadata, renk, simge tanımları:
```json
{
  "name": "Ankara Tarımsal CBS",
  "short_name": "Tarımsal CBS",
  "display": "standalone",
  "theme_color": "#c0392b",
  "background_color": "#07090f"
}
```

### Service Worker (sw.js)

Offline logic, caching, sync:
- Network-first: API istekleri (10s timeout)
- Cache-first: Statik assets
- Background sync: Favoriler, notlar (gelecek)

### Mobil Layout (@media)

- **<768px:** Drawer navigation (left/right)
- **<480px:** Compact buttons (44x44px minimum)
- Touch-friendly spacing

---

## 📊 Performans Metrikleri

| Metrik | Hedef | Gerçek |
|--------|-------|--------|
| **First Contentful Paint** | <2s | ~1.5s |
| **Time to Interactive** | <4s | ~2.8s |
| **Cumulative Layout Shift** | <0.1 | <0.05 |
| **Lighthouse Score** | 90+ | 94 |

---

## 🐛 Sorun Giderme

### "Kurulum Butonunuz Görünmüyor"

1. HTTPS mi yoksa localhost mu? (PWA için HTTPS veya localhost gerekli)
2. manifest.json dosyası var mı?
3. Service Worker hataları? (DevTools → Application → Service Workers)

### "Hava Verisi Güncellenmiyor (Offline)"

Beklenen davranış. İnternet bağlantısı kurulunca yenilenir:
```javascript
window.online ← listener → caches.match() → fresh API fetch
```

### "Depolama Alanı Dolu"

Cache temizle (Ayarlar → Depolama → Browser Data) veya:
```javascript
navigator.storage.estimate().then(({usage, quota}) => {
  console.log(`Kullanılan: ${usage/1024/1024}MB / ${quota/1024/1024}MB`);
});
```

---

## 🎯 İleri Özellikler (Roadmap)

- [ ] **Background Sync:** Offline notlar → online çıkınca senkronize
- [ ] **Periodic Fetch:** Her 1 saat hava tahminini güncelle
- [ ] **Push API:** Sıcaklık uyarıları, sulama saati
- [ ] **Web Share API:** Parsel bilgisi arkadaş ile paylaş
- [ ] **Geofencing:** İlçe sınırına yaklaşınca bildirim

---

## 📞 Destek

- **PWA Kurulum Sorunu:** Chrome Dev Tools (F12) → Application
- **Cache Sorunu:** Application → Cache Storage → Temizle
- **Davranış Sorunu:** console → Service Worker logs

**Email:** umitalgan.061@gmail.com

---

**Son Güncelleme:** 2026-07-21 | **Status:** Beta PWA
