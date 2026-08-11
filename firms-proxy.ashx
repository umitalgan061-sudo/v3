<%@ WebHandler Language="C#" Class="FirmsProxy" %>
<%@ Assembly Name="System.Web.Extensions, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" %>

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Net;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;

// ═══════════════════════════════════════════════════════════════════════════
// NASA FIRMS — AKTİF YANGIN NOKTA VERİSİ PROXY (VIIRS, 375 m, gerçek zamanlıya
// en yakın ücretsiz kaynak)
// ═══════════════════════════════════════════════════════════════════════════
// Kaynak: https://firms.modaps.eosdis.nasa.gov/api/area/  (resmi NASA FIRMS API)
// Bu uç CSV döner (WMS gibi sadece görsel değil — her nokta için gerçek
// parlaklık/güven/FRP değeri içerir); bu dosya sunucu tarafında 3 VIIRS
// kaynağını (Suomi-NPP + NOAA-20 + NOAA-21) çekip birleştirir ve tıklanabilir
// GeoJSON noktalarına çevirir. Tarayıcıdan doğrudan çağrılmıyor çünkü:
//   1) FIRMS CSV ucu tarayıcıya CORS izni vermeyebilir,
//   2) MAP_KEY'in 5000 istek/10dk limitini sunucu tarafında önbellekle korumak gerekir.
//
// KURULUM (bir kere yapılır):
//   1) https://firms.modaps.eosdis.nasa.gov/api/map_key/ adresinden ÜCRETSİZ
//      bir MAP_KEY alın (e-posta ile anında gelir).
//   2) Aşağıdaki MAP_KEY sabitini doldurun.
//   3) Bu dosyayı index.html ile aynı klasöre yükleyin.
//   4) https://.../firms-proxy.ashx?debug=1 açıp "features" dizisinin dolu
//      geldiğini doğrulayın.
// ═══════════════════════════════════════════════════════════════════════════

public class FirmsProxy : IHttpHandler
{
    // ── SADECE BU SATIRI DOLDUR ──────────────────────────────────────────
    private const string MAP_KEY = "c5e5580d640660138db61a2c796928c7";
    // ──────────────────────────────────────────────────────────────────────

    // Türkiye'nin tamamı + komşu ülkelerden biraz taşan pay: minLon,minLat,maxLon,maxLat
    private const string AREA = "24.0,34.0,46.0,43.0";

    // Ücretsiz olarak en sık tazelenen, dünya çapında sunulan 3 VIIRS kaynağı
    // (375 m çözünürlük). Üçü birleşince aynı nokta günde birkaç kez taranır —
    // MODIS'ten (1 km, günde 2 geçiş) daha sık ve daha yüksek çözünürlüklüdür.
    private static readonly string[] SOURCES =
        { "VIIRS_SNPP_NRT", "VIIRS_NOAA20_NRT", "VIIRS_NOAA21_NRT" };

    // NASA "Near Real-Time" verisini geçişten en fazla ~3 saat içinde yayınlıyor;
    // bu yüzden 15 dk'lık önbellek gerçek veri tazeliğini geride bırakmaz ama
    // MAP_KEY kotasını (5000/10dk) korur.
    private static readonly TimeSpan CACHE_TTL = TimeSpan.FromMinutes(15);
    private static CacheEntry _cache;
    private static readonly object _lock = new object();
    private class CacheEntry { public string Json; public DateTime Expires; }

    public bool IsReusable { get { return true; } }

    public void ProcessRequest(HttpContext ctx)
    {
        try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { }

        var res = ctx.Response;
        bool debug = ctx.Request.QueryString["debug"] == "1";

        if (MAP_KEY.StartsWith("PASTE_"))
        {
            WriteJson(res, ErrJson("Proxy henüz yapılandırılmadı: firms-proxy.ashx içindeki MAP_KEY satırını " +
                "https://firms.modaps.eosdis.nasa.gov/api/map_key/ adresinden alacağınız ücretsiz anahtarla doldurun."));
            return;
        }

        lock (_lock)
        {
            if (_cache != null && _cache.Expires > DateTime.UtcNow)
            {
                WriteJson(res, _cache.Json);
                return;
            }
        }

        try
        {
            var features = new List<object>();
            var errors = new List<string>();

            foreach (var src in SOURCES)
            {
                string url = "https://firms.modaps.eosdis.nasa.gov/api/area/csv/" + MAP_KEY + "/" + src + "/" + AREA + "/1";
                string csv;
                try
                {
                    var wc = new WebClient();
                    wc.Encoding = Encoding.UTF8;
                    wc.Headers[HttpRequestHeader.UserAgent] = "Mozilla/5.0 (compatible; TarimsalCBS/1.0)";
                    csv = wc.DownloadString(url);
                }
                catch (Exception ex) { errors.Add(src + ": " + ex.Message); continue; }

                ParseCsvInto(csv, src, features, errors);
            }

            var fc = new Dictionary<string, object> {
                { "ok", true },
                { "type", "FeatureCollection" },
                { "features", features },
                { "count", features.Count },
                { "generatedAt", DateTime.UtcNow.ToString("o") }
            };
            if (debug) fc["_debugErrors"] = errors;

            var serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            string json = serializer.Serialize(fc);
            lock (_lock) { _cache = new CacheEntry { Json = json, Expires = DateTime.UtcNow.Add(CACHE_TTL) }; }
            WriteJson(res, json);
        }
        catch (Exception ex)
        {
            WriteJson(res, ErrJson("Sunucu hatası: " + ex.Message));
        }
    }

    // CSV başlığındaki sütun adlarına göre esnek ayrıştırma — FIRMS farklı
    // kaynaklarda (VIIRS/MODIS) küçük sütun farklılıkları döndürebiliyor.
    private static void ParseCsvInto(string csv, string src, List<object> features, List<string> errors)
    {
        if (string.IsNullOrEmpty(csv)) return;
        var lines = csv.Replace("\r", "").Split('\n');
        if (lines.Length < 2) return;

        var header = lines[0].Split(',');
        int iLat = IndexOf(header, "latitude");
        int iLon = IndexOf(header, "longitude");
        int iBriT4 = IndexOf(header, "bright_ti4");
        int iBriT5 = IndexOf(header, "bright_ti5");
        int iConf = IndexOf(header, "confidence");
        int iFrp = IndexOf(header, "frp");
        int iDate = IndexOf(header, "acq_date");
        int iTime = IndexOf(header, "acq_time");
        int iSat = IndexOf(header, "satellite");
        int iDn = IndexOf(header, "daynight");

        if (iLat < 0 || iLon < 0)
        {
            errors.Add(src + ": beklenen sütunlar bulunamadı (API yanıt biçimi değişmiş olabilir)");
            return;
        }

        for (int i = 1; i < lines.Length; i++)
        {
            var line = lines[i];
            if (line.Length == 0) continue;
            var cols = line.Split(',');
            if (cols.Length <= iLat || cols.Length <= iLon) continue;

            double lat, lon;
            if (!double.TryParse(cols[iLat], NumberStyles.Float, CultureInfo.InvariantCulture, out lat)) continue;
            if (!double.TryParse(cols[iLon], NumberStyles.Float, CultureInfo.InvariantCulture, out lon)) continue;

            var props = new Dictionary<string, object> {
                { "satellite",   Get(cols, iSat)   ?? src },
                { "confidence",  Get(cols, iConf) },
                { "frp",         Get(cols, iFrp) },
                { "bright_ti4",  Get(cols, iBriT4) },
                { "bright_ti5",  Get(cols, iBriT5) },
                { "acq_date",    Get(cols, iDate) },
                { "acq_time",    Get(cols, iTime) },
                { "daynight",    Get(cols, iDn) }
            };

            features.Add(new Dictionary<string, object> {
                { "type", "Feature" },
                { "geometry", new Dictionary<string, object> {
                    { "type", "Point" }, { "coordinates", new object[] { lon, lat } }
                }},
                { "properties", props }
            });
        }
    }

    private static string Get(string[] cols, int idx)
    {
        if (idx < 0 || idx >= cols.Length) return null;
        var v = cols[idx];
        return string.IsNullOrEmpty(v) ? null : v;
    }

    private static int IndexOf(string[] arr, string val)
    {
        for (int i = 0; i < arr.Length; i++) if (arr[i] == val) return i;
        return -1;
    }

    private static string ErrJson(string msg)
    {
        return new JavaScriptSerializer().Serialize(new { ok = false, error = msg, features = new object[0] });
    }

    private static void WriteJson(HttpResponse res, string json)
    {
        res.ContentType = "application/json; charset=utf-8";
        res.Cache.SetCacheability(HttpCacheability.Public);
        res.Cache.SetMaxAge(TimeSpan.FromMinutes(10));
        res.Write(json);
    }
}
