# Ankara Tarımsal CBS Platformu – Veri Kaynakları

## 📡 Entegre Edilen Veri Kaynakları

### 1. **GIBS IMERG – Küresel Yağış Verileri**
**Status**: ✅ WMS Entegre  
**Güncelleme Sıklığı**: 30 dakikalık  
**Çözünürlük**: 10 km global

#### API Bilgisi
- **WMS Endpoint**: `https://gibs.earthdata.nasa.gov/wms/epsg3857/best/`
- **Layer**: `IMERG_CalibratedPrecipitationRate_IR_Cloud_Top`
- **Format**: PNG (transparent)
- **Auth**: Açık (API key gerekli değil)

#### Parametreler
```
?service=WMS&version=1.3.0&request=GetMap
&layers=IMERG_CalibratedPrecipitationRate_IR_Cloud_Top
&styles=&format=image/png&transparent=true
&crs=EPSG:3857&TIME=2024-07-03T12:00:00Z
```

#### Dokümantasyon
- GIBS Kataloğu: https://gibs.earthdata.nasa.gov/
- IMERG Açıklaması: https://pmm.nasa.gov/data-access/imerg-data
- Canlı Zamanlı Veri: Son ~1-2 saat gecikmeli

---

### 2. **Open-Meteo 48H Grid Tahmin – Sıcaklık & Yağış**
**Status**: ✅ API Entegre  
**Güncelleme Sıklığı**: Saatlik  
**Çözünürlük**: 0.25° (~25 km)

#### API Bilgisi
- **Endpoint**: `https://api.open-meteo.com/v1/forecast`
- **Auth**: Açık (API key gerekli değil)
- **Rate Limit**: Unlimited (non-commercial)

#### Sorgu Örneği
```bash
https://api.open-meteo.com/v1/forecast?\
latitude=39.93&longitude=32.86&\
hourly=temperature_2m,precipitation,weather_code,wind_speed_10m&\
forecast_hours=48&\
timezone=Europe/Istanbul
```

#### Dönen Veri Yapısı
```json
{
  "hourly": {
    "time": ["2024-07-03T00:00", ...],
    "temperature_2m": [22.5, 23.1, ...],
    "precipitation": [0.0, 1.2, ...],
    "wind_speed_10m": [8.3, 9.1, ...]
  }
}
```

#### Dokümantasyon
- API Belgeleri: https://open-meteo.com/en/docs
- Parametreler: https://open-meteo.com/en/docs/forecast-api
- WebGL Görselleştirme: https://open-meteo.com/en/docs/visualization

---

### 3. **HLS – Harmonized Landsat-Sentinel Uydu Görüntüleri**
**Status**: 🔄 Entegre Edilmiyor (Alternatif: Sentinel-2 Cloudless)  
**Güncelleme Sıklığı**: 2-3 günlük (composite)  
**Çözünürlük**: 30 m (HLS) → TMS olarak 10+ zoom

#### HLS Veri Erişim Yöntemleri

##### A. NASA USGS LP DAAC API (Tercih Edilen)
```
https://lpdaacsvc.cr.usgs.gov/API/HLS/1.2/
```
- **Auth**: Earthdata Login (ücretsiz)
- **Veri Formatı**: GeoTIFF (S3 cloud-optimized)
- **Açıklama**: Landsat-8/9 + Sentinel-2 harmonize edilmiş ürünü

##### B. AWS Open Data Program (Alternatif)
```
s3://hls-satellite-data-us/
```
- **Region**: us-west-2
- **Veri Formatı**: COG (Cloud-Optimized GeoTIFF)
- **Ücretsiz**: Evet (AWS data transfer ücretlendirilebilir)

##### C. Alternatif: Sentinel-2 Cloudless (EOX)
```
https://tiles.geosmartmap.com/ArcGIS/rest/services/Basemaps/S2_2024_true_color/MapServer/
```
- **Avantaj**: HLS kadar güzel, TMS olarak hazır
- **Çözünürlük**: 10 m (Sentinel-2 native)
- **Erişim**: Ücretsiz, CC-BY

#### Entegrasyon Stratejisi
1. **Web**: TMS (tiles.geosmartmap.com) kullan
2. **İndirme**: WCS (Web Coverage Service) ile HLS raw GeoTIFF al
3. **Analiz**: GDAL/rasterio ile sunucu tarafında işle

#### Dokümantasyon
- NASA HLS: https://hls.gsfc.nasa.gov/
- USGS API: https://lpdaacsvc.cr.usgs.gov/API/HLS/docs
- AWS HLS Data: https://registry.opendata.aws/hls/
- EOX Sentinel-2: https://www.eox.at/

---

### 4. **Karbon Stoğu – GEDI L4B + ASTER GDEM**
**Status**: 🔄 Entegre Edilmiyor (Pilot versyon)  
**Güncelleme Sıklığı**: Yıllık  
**Çözünürlük**: 100 m (GEDI), 30 m (ASTER)

#### GEDI L4B Gridded Biomass

##### A. NASA DAAC Erişim
```
https://daac.ornl.gov/GEDI/guides/GEDI04_B_MW019MW138_02_002_05_R41000_MU.pdf
```
- **Dataset**: GEDI04_B_MW019MW138 (Aboveground Biomass Density)
- **Version**: v2.1 (Orman tarafında)
- **Format**: HDF5 / GeoTIFF
- **Çözünürlük**: 100 m grid

##### B. NASA Earthdata Search
```
https://search.earthdata.nasa.gov/
```
- Koleksiyon: `GEDI04_B_MW_01_002_04`
- İndirme: HTTPS or OPeNDAP

#### ASTER GDEM v3 – Yükseklik & Eğim
```
https://lpdaacsvc.cr.usgs.gov/appeears/
```
- **Veri**: ASTER Global DEM v3
- **Çözünürlük**: 30 m
- **Kapsam**: Global (-83°N to 83°S)

#### Global Forest Watch Carbon API
```
https://www.globalforestwatch.org/
```
- **Endpoint**: GFW API (Tree Cover Loss + Carbon Risk)
- **Şeffaflık**: Açık veri
- **Entegrasyon**: Vector API for tiles

#### Karbon Hesaplama Formülü
```
Total Carbon Stock (ton C) = 
  Biomass Density (Mg/ha) × 
  Forest Area (ha) × 
  0.47 (Carbon fraction)
```

#### Dokümantasyon
- GEDI Mission: https://gedi.jpl.nasa.gov/
- GEDI Ürünleri: https://lpdaac.usgs.gov/products/gedi04_bv002/
- ASTER GDEM: https://lpdaacsvc.cr.usgs.gov/appeears/
- GFW Carbon: https://www.globalforestwatch.org/

---

## 🔄 Entegrasyon Durumu

| Katman | Durum | Zorluk | Notlar |
|--------|-------|--------|--------|
| GIBS IMERG | ✅ Hazır | Düşük | WMS → Doğrudan layer |
| Open-Meteo Grid 48H | ✅ Hazır | Düşük | JSON API → GeoJSON grid |
| HLS Uydu | 🟡 Alternatif | Orta | Sentinel-2 Cloudless TMS kullan |
| Karbon Stoğu | 🟡 Pilot | Yüksek | GEDI + GFW fusion gerekli |

---

## 📥 Veri İndirme Rehberi

### GIBS IMERG Arşiv (Geçmiş Veri)
```bash
# Direct Link Example (7 gün önceki)
https://gibs.earthdata.nasa.gov/wmts-webmerc/IMERG_CalibratedPrecipitationRate_IR_Cloud_Top/default//GoogleMapsCompatible_Level8/{z}/{y}/{x}.png?TIME=2024-06-26
```

### Open-Meteo Geçmiş 90 Gün
```bash
# Archive API
https://archive-api.open-meteo.com/v1/archive?\
latitude=39.93&longitude=32.86&\
date=2024-04-04&\
hourly=temperature_2m,precipitation
```

### HLS GeoTIFF İndirme (Yerel Analiz İçin)
```python
# Python örneği
from earthaccess import search, download
results = search(
    short_name="HLS",
    count=10,
    bbox=[31.5, 38.5, 34.0, 41.0]  # Ankara bölgesi
)
files = download(results, "./data")
```

### GEDI L4B İndirme
```python
from requests.auth import HTTPBasicAuth
import requests

url = "https://daac.ornl.gov/daacbin/getfile.pl?ent_id=GEDI04_B_2019_08_02_00_00_06_01_002_02"
auth = HTTPBasicAuth(username, password)  # Earthdata credentials
response = requests.get(url, auth=auth)
```

---

## 🔐 Kimlik Doğrulama

### Earthdata Login (NASA DAAC)
1. Kaydol: https://urs.earthdata.nasa.gov/users/new
2. Profil → Yetkilendirmeler: HLS ve GEDI uygulamalarını onaylat
3. Credentials → Yazılım → Token/API Key oluştur

### Open-Meteo
- **API Key**: Gerekli değil (ücretsiz tier)
- **Commercial**: Ücretli API key mevcut

### AWS S3 Access
```bash
# Opsiyonel (HLS S3 doğrudan erişim)
aws configure
aws s3 ls s3://hls-satellite-data-us/
```

---

## 📊 Performans Optimizasyonu

### WMS/TMS Caching
```javascript
// Leaflet TMS caching (local storage)
L.tileLayer(...).addTo(map);
// → Browser cache + CDN (gibs.earthdata.nasa.gov)
```

### API Rate Limiting
- **GIBS**: Sınırsız
- **Open-Meteo**: Sınırsız (non-commercial)
- **DAAC**: 30 req/min (ücretsiz tier)

### Tile Size Optimizasyon
- **Zoom 8 ve altı**: 256×256 px tiles (GIBS IMERG)
- **Zoom 9+**: 512×512 px (Sentinel-2 Cloudless)

---

## 🛠️ Sorun Giderme

### GIBS IMERG Görünmüyor
- [ ] TIME parametresi doğru mu? (UTC)
- [ ] Zoom seviyesi ≤ 8 mi?
- [ ] CORS enabled mi? (GIBS → Yes)

### Open-Meteo Verisi Eksik
- [ ] API key kullanıyor musun? (gerekli değil, ama rate limit var)
- [ ] Tarih aralığı valid mi? (forecast 16 gün, archive 90 gün)

### HLS Veri Erişimi
- [ ] Earthdata Login'e giriş yaptın mı?
- [ ] Bölge koordinatları doğru mu?
- [ ] Bulut örtüsü yüksek mi? (HLS bulut kalibrasyonlu ama)

### GEDI İndirme Başarısız
- [ ] NASA DAAC credentials geçerli mi?
- [ ] HDF5 library yüklü mü? (`gdal`, `h5py`)

---

## 📚 Referanslar

1. **NASA GIBS Documentation**
   - https://gibs.earthdata.nasa.gov/
   - https://gibs.earthdata.nasa.gov/wmts/

2. **Open-Meteo API**
   - https://open-meteo.com/
   - GitHub: https://github.com/open-meteo

3. **HLS Mission**
   - https://hls.gsfc.nasa.gov/
   - Data: https://lpdaac.usgs.gov/products/hlss30v002/

4. **GEDI Mission**
   - https://gedi.jpl.nasa.gov/
   - Science: https://gedi.jpl.nasa.gov/about

5. **Karbon Monitoring**
   - Global Forest Watch: https://www.globalforestwatch.org/
   - Carbon Monitoring System: https://daac.ornl.gov/CMS/

---

*Son Güncelleme: 2026-07-03*  
*Platform: Ankara Tarımsal CBS & Hava Platformu*
