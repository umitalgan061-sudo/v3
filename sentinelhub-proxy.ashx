<%@ WebHandler Language="C#" Class="SentinelHubProxy" %>
<%@ Assembly Name="System.Web.Extensions, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" %>

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;

// ═══════════════════════════════════════════════════════════════════════════
// SENTINEL HUB / COPERNICUS DATA SPACE ECOSYSTEM — GÜVENLİ SUNUCU-TARAFI PROXY
// ═══════════════════════════════════════════════════════════════════════════
// Bu dosya sunucuda ÇALIŞTIRILIR, tarayıcıya KAYNAK KODU OLARAK ASLA gönderilmez
// (IIS/ASP.NET .ashx dosyalarını derleyip sadece ÇIKTISINI yollar). Bu yüzden
// CLIENT_SECRET'i burada tutmak, index.html'e (istemci tarafı, herkese açık
// statik dosya) yazmaktan güvenlidir.
//
// KURULUM (bir kere yapılır):
//   1) CDSE panelinde (shapps.dataspace.copernicus.eu/dashboard/#/account/settings)
//      eski OAuth Client'ı (TARIMSAL_CBS_APP) SİL ve YENİ bir tane oluştur —
//      eski secret index.html'de bir süre açık kaldığı için güvenilir sayılmamalı.
//   2) Aşağıdaki CLIENT_ID ve CLIENT_SECRET sabitlerini yeni değerlerle değiştir.
//   3) Bu dosyayı index.html ile AYNI klasöre (sunucuya) yükle.
//   4) Tarayıcıda https://cbs.ankara.bel.tr/tarimsalcbs/sentinelhub-proxy.ashx?action=tile&layer=s2rgb&z=10&x=615&y=391
//      adresini aç — PNG bir görüntü dönmeli. Hata alırsan &debug=1 ekleyip
//      dönen metni bana ilet.
// ═══════════════════════════════════════════════════════════════════════════

public class SentinelHubProxy : IHttpHandler
{
    // ── SADECE BU İKİ SATIRI DOLDUR ──────────────────────────────────────
    private const string CLIENT_ID     = "sh-979dbc39-38dc-4514-9ce7-59c8d6762add";
    private const string CLIENT_SECRET = "zWjea1aqiCmMqNHDhsPqKZ8usDck4rcB";
    // ──────────────────────────────────────────────────────────────────────

    private const string TOKEN_URL   = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token";
    private const string PROCESS_URL = "https://sh.dataspace.copernicus.eu/api/v1/process";
    private const string STATS_URL   = "https://sh.dataspace.copernicus.eu/api/v1/statistics";

    private static string _token;
    private static DateTime _tokenExpiry = DateTime.MinValue;
    private static readonly object _tokenLock = new object();

    // Basit bellek-içi görüntü önbelleği — aynı tile'ı tekrar tekrar çekip
    // ücretsiz aylık kotayı (10.000 processing unit) boşa harcamamak için.
    private static readonly ConcurrentDictionary<string, CacheEntry> _cache = new ConcurrentDictionary<string, CacheEntry>();
    private static readonly TimeSpan CACHE_TTL = TimeSpan.FromHours(6);

    private class CacheEntry { public byte[] Bytes; public string ContentType; public DateTime Expires; }

    public bool IsReusable { get { return true; } }

    public void ProcessRequest(HttpContext ctx)
    {
        // .NET Framework 4.0 varsayılan olarak eski TLS sürümlerini dener; CDSE
        // sadece TLS 1.2+ kabul ediyor. (SecurityProtocolType)3072 = Tls12 — bu
        // enum değeri .NET 4.5'te eklendi ama sayısal karşılığı 4.0'da da çalışır.
        try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { }

        var req = ctx.Request;
        var res = ctx.Response;
        bool debug = req.QueryString["debug"] == "1";

        if (CLIENT_ID.StartsWith("PASTE_") || CLIENT_SECRET.StartsWith("PASTE_"))
        {
            WriteError(res, debug, "Proxy henüz yapılandırılmadı: sentinelhub-proxy.ashx içindeki CLIENT_ID / CLIENT_SECRET satırlarını doldurup tekrar yükleyin.");
            return;
        }

        try
        {
            string action = req.QueryString["action"];
            if (action == "tile") HandleTile(ctx, debug);
            else if (action == "point") HandlePoint(ctx, debug);
            else WriteError(res, debug, "Bilinmeyen action. Kullanım: ?action=tile veya ?action=point");
        }
        catch (Exception ex)
        {
            WriteError(res, debug, "Sunucu hatası: " + ex.Message);
        }
    }

    // ── TILE: harita üstünde görsel katman (PNG döner) ──────────────────────
    private void HandleTile(HttpContext ctx, bool debug)
    {
        var req = ctx.Request; var res = ctx.Response;
        string layer = req.QueryString["layer"];
        int z, x, y;
        if (!int.TryParse(req.QueryString["z"], out z) || !int.TryParse(req.QueryString["x"], out x) || !int.TryParse(req.QueryString["y"], out y))
        { WriteError(res, debug, "z/x/y parametreleri eksik/hatalı."); return; }

        string cacheKey = "tile:" + layer + ":" + z + ":" + x + ":" + y;
        CacheEntry cached;
        if (_cache.TryGetValue(cacheKey, out cached) && cached.Expires > DateTime.UtcNow)
        { WriteBytes(res, cached.Bytes, cached.ContentType); return; }

        double minLon = TileToLon(x, z), maxLon = TileToLon(x + 1, z);
        double maxLat = TileToLat(y, z), minLat = TileToLat(y + 1, z);

        string collection, evalscript;
        if (!GetLayerConfig(layer, out collection, out evalscript))
        { WriteError(res, debug, "Bilinmeyen layer: " + layer); return; }

        var body = new JavaScriptSerializer().Serialize(new
        {
            input = new
            {
                bounds = new
                {
                    bbox = new[] { minLon, minLat, maxLon, maxLat },
                    properties = new { crs = "http://www.opengis.net/def/crs/OGC/1.3/CRS84" }
                },
                data = new object[] {
                    new {
                        type = collection,
                        dataFilter = BuildDataFilter(collection)
                    }
                }
            },
            output = new
            {
                width = 256,
                height = 256,
                responses = new object[] { new { identifier = "default", format = new { type = "image/png" } } }
            },
            evalscript = evalscript
        });

        byte[] png;
        string err;
        if (!PostForBytes(PROCESS_URL, body, "image/png", out png, out err))
        { WriteError(res, debug, "Process API hatası: " + err); return; }

        _cache[cacheKey] = new CacheEntry { Bytes = png, ContentType = "image/png", Expires = DateTime.UtcNow.Add(CACHE_TTL) };
        WriteBytes(res, png, "image/png");
    }

    // ── POINT: bir koordinat için GERÇEK sayısal değer (JSON döner) ─────────
    private void HandlePoint(HttpContext ctx, bool debug)
    {
        var req = ctx.Request; var res = ctx.Response;
        string layer = req.QueryString["layer"];
        double lat, lon;
        if (!double.TryParse(req.QueryString["lat"], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out lat) ||
            !double.TryParse(req.QueryString["lon"], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out lon))
        { WriteError(res, debug, "lat/lon parametreleri eksik/hatalı."); return; }

        string cacheKey = "pt:" + layer + ":" + lat.ToString("F4") + ":" + lon.ToString("F4");
        CacheEntry cached;
        if (_cache.TryGetValue(cacheKey, out cached) && cached.Expires > DateTime.UtcNow)
        { WriteBytes(res, cached.Bytes, "application/json"); return; }

        string collection, statEvalscript, outputId;
        if (!GetStatConfig(layer, out collection, out statEvalscript, out outputId))
        { WriteError(res, debug, "Bilinmeyen layer: " + layer); return; }

        double d = 0.0006; // ~60m çaplı küçük bir kutu, tek nokta gibi davranır
        var body = new JavaScriptSerializer().Serialize(new
        {
            input = new
            {
                bounds = new
                {
                    bbox = new[] { lon - d, lat - d, lon + d, lat + d },
                    properties = new { crs = "http://www.opengis.net/def/crs/OGC/1.3/CRS84" }
                },
                data = new object[] {
                    new {
                        type = collection,
                        dataFilter = BuildDataFilter(collection)
                    }
                }
            },
            aggregation = new
            {
                timeRange = new { from = DateTime.UtcNow.AddDays(-30).ToString("yyyy-MM-ddT00:00:00Z"), to = DateTime.UtcNow.ToString("yyyy-MM-ddT23:59:59Z") },
                aggregationInterval = new { of = "P30D" },
                width = 32,
                height = 32,
                evalscript = statEvalscript
            },
            calculations = new System.Collections.Generic.Dictionary<string, object> {
                { outputId, new { statistics = new { def = new { } } } }
            }
        });

        byte[] resp; string err;
        if (!PostForBytes(STATS_URL, body, "application/json", out resp, out err))
        { WriteError(res, debug, "Statistical API hatası: " + err); return; }

        string json = Encoding.UTF8.GetString(resp);
        double? mean = ExtractMean(json, outputId);
        string outJson = new JavaScriptSerializer().Serialize(new { ok = mean.HasValue, value = mean, layer = layer, lat = lat, lon = lon });
        byte[] outBytes = Encoding.UTF8.GetBytes(outJson);

        _cache[cacheKey] = new CacheEntry { Bytes = outBytes, ContentType = "application/json", Expires = DateTime.UtcNow.Add(CACHE_TTL) };
        WriteBytes(res, outBytes, "application/json");
    }

    // Optik (kameralı) uydu koleksiyonları bulut örtüsünden gerçekten etkilenir;
    // bu yüzden bu koleksiyonlarda "mostRecent" (son 30 gündeki EN SON görüntü,
    // bulutlu olsa bile) yerine "leastCC" (en az bulutlu görüntü) kullanılır —
    // sidebar'daki "son 30 gün bulutsuz" etiketiyle gerçek davranış eşleşsin diye.
    // Ayrıca aday görüntü havuzunu da %40 bulut üstü sahnelerden temizlemek için
    // maxCloudCoverage eklenir. SAR (sentinel-1-grd, buluttan zaten etkilenmez) ve
    // Sentinel-5P (atmosfer, farklı bir kalite modeli var) bu filtreye dahil değil.
    private static readonly HashSet<string> CLOUD_AFFECTED_COLLECTIONS =
        new HashSet<string> { "sentinel-2-l2a", "sentinel-3-slstr" };

    private static object BuildDataFilter(string collection)
    {
        var timeRange = new { from = DateTime.UtcNow.AddDays(-30).ToString("yyyy-MM-ddT00:00:00Z"),
                               to   = DateTime.UtcNow.ToString("yyyy-MM-ddT23:59:59Z") };
        if (CLOUD_AFFECTED_COLLECTIONS.Contains(collection))
            return new { timeRange = timeRange, mosaickingOrder = "leastCC", maxCloudCoverage = 40 };
        return new { timeRange = timeRange, mosaickingOrder = "mostRecent" };
    }

    // ── Katman tanımları ──────────────────────────────────────────────────
    private static bool GetLayerConfig(string layer, out string collection, out string evalscript)
    {
        collection = null; evalscript = null;
        switch (layer)
        {
            case "s2rgb":
                collection = "sentinel-2-l2a";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[\"B04\",\"B03\",\"B02\"],output:{bands:3}};}\nfunction evaluatePixel(s){return [2.5*s.B04, 2.5*s.B03, 2.5*s.B02];}";
                return true;
            case "ndvi10":
                collection = "sentinel-2-l2a";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[\"B04\",\"B08\"],output:{bands:3}};}\n"
                    + "function evaluatePixel(s){var n=(s.B08-s.B04)/(s.B08+s.B04+0.0001);\n"
                    + "if(n<0)return[0.66,0.66,0.66];\n"
                    + "if(n<0.2)return[0.80,0.60,0.20];\n"
                    + "if(n<0.4)return[0.90,0.80,0.20];\n"
                    + "if(n<0.6)return[0.60,0.80,0.20];\n"
                    + "return[0.10,0.55,0.10];}";
                return true;
            case "s1sar":
                collection = "sentinel-1-grd";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[\"VV\"],output:{bands:1}};}\n"
                    + "function evaluatePixel(s){var db=10*Math.log(s.VV)/Math.LN10; var v=(db+25)/25; v=Math.max(0,Math.min(1,v)); return [v];}";
                return true;
            case "s3lst":
                collection = "sentinel-3-slstr";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[\"S8\"],output:{bands:3}};}\n"
                    + "function evaluatePixel(s){var c=s.S8-273.15;\n"
                    + "if(c<0)return[0.2,0.2,0.8];\n"
                    + "if(c<15)return[0.2,0.6,0.9];\n"
                    + "if(c<25)return[0.9,0.9,0.3];\n"
                    + "if(c<35)return[0.9,0.5,0.1];\n"
                    + "return[0.8,0.1,0.1];}";
                return true;
        }
        return false;
    }

    private static bool GetStatConfig(string layer, out string collection, out string evalscript, out string outputId)
    {
        collection = null; evalscript = null; outputId = "val";
        switch (layer)
        {
            case "ndvi10":
                collection = "sentinel-2-l2a";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[{bands:[\"B04\",\"B08\",\"dataMask\"]}],output:[{id:\"val\",bands:1},{id:\"dataMask\",bands:1}]};}\n"
                    + "function evaluatePixel(s){var n=(s.B08-s.B04)/(s.B08+s.B04+0.0001); return {val:[n], dataMask:[s.dataMask]};}";
                return true;
            case "s1sar":
                collection = "sentinel-1-grd";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[{bands:[\"VV\",\"dataMask\"]}],output:[{id:\"val\",bands:1},{id:\"dataMask\",bands:1}]};}\n"
                    + "function evaluatePixel(s){var db=10*Math.log(s.VV)/Math.LN10; return {val:[db], dataMask:[s.dataMask]};}";
                return true;
            case "s3lst":
                collection = "sentinel-3-slstr";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[{bands:[\"S8\",\"dataMask\"]}],output:[{id:\"val\",bands:1},{id:\"dataMask\",bands:1}]};}\n"
                    + "function evaluatePixel(s){return {val:[s.S8-273.15], dataMask:[s.dataMask]};}";
                return true;
            case "s5p":
                collection = "sentinel-5p-l2";
                evalscript = "//VERSION=3\nfunction setup(){return{input:[{bands:[\"NO2\",\"dataMask\"]}],output:[{id:\"val\",bands:1},{id:\"dataMask\",bands:1}]};}\n"
                    + "function evaluatePixel(s){return {val:[s.NO2], dataMask:[s.dataMask]};}";
                return true;
        }
        return false;
    }

    private static double? ExtractMean(string json, string outputId)
    {
        try
        {
            var jss = new JavaScriptSerializer();
            var root = jss.Deserialize<System.Collections.Generic.Dictionary<string, object>>(json);
            object dataObj;
            if (!root.TryGetValue("data", out dataObj)) return null;
            var dataArr = (System.Collections.ArrayList)dataObj;
            if (dataArr.Count == 0) return null;
            var first = (System.Collections.Generic.Dictionary<string, object>)dataArr[0];
            var outputs = (System.Collections.Generic.Dictionary<string, object>)first["outputs"];
            var outp = (System.Collections.Generic.Dictionary<string, object>)outputs[outputId];
            var bands = (System.Collections.Generic.Dictionary<string, object>)outp["bands"];
            var b0 = (System.Collections.Generic.Dictionary<string, object>)bands["B0"];
            var stats = (System.Collections.Generic.Dictionary<string, object>)b0["stats"];
            object meanObj;
            if (stats.TryGetValue("mean", out meanObj) && meanObj != null) return Convert.ToDouble(meanObj);
            return null;
        }
        catch { return null; }
    }

    // ── OAuth token (client_credentials), bellekte 55 dk önbelleklenir ──────
    private static string GetToken(out string error)
    {
        error = null;
        lock (_tokenLock)
        {
            if (_token != null && _tokenExpiry > DateTime.UtcNow) return _token;
            try
            {
                var wc = new WebClient();
                wc.Headers[HttpRequestHeader.ContentType] = "application/x-www-form-urlencoded";
                var data = "grant_type=client_credentials&client_id=" + Uri.EscapeDataString(CLIENT_ID)
                    + "&client_secret=" + Uri.EscapeDataString(CLIENT_SECRET);
                byte[] respBytes = wc.UploadData(TOKEN_URL, "POST", Encoding.UTF8.GetBytes(data));
                string respStr = Encoding.UTF8.GetString(respBytes);
                var jss = new JavaScriptSerializer();
                var obj = jss.Deserialize<System.Collections.Generic.Dictionary<string, object>>(respStr);
                _token = (string)obj["access_token"];
                int expiresIn = Convert.ToInt32(obj["expires_in"]);
                _tokenExpiry = DateTime.UtcNow.AddSeconds(Math.Max(60, expiresIn - 60));
                return _token;
            }
            catch (WebException wex)
            {
                string body = "";
                if (wex.Response != null)
                    using (var sr = new StreamReader(wex.Response.GetResponseStream())) body = sr.ReadToEnd();
                error = "Token alınamadı: " + wex.Message + " " + body;
                return null;
            }
            catch (Exception ex) { error = "Token alınamadı: " + ex.Message; return null; }
        }
    }

    private static bool PostForBytes(string url, string jsonBody, string accept, out byte[] result, out string error)
    {
        result = null;
        string tokErr;
        string token = GetToken(out tokErr);
        if (token == null) { error = tokErr; return false; }

        try
        {
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "POST";
            request.ContentType = "application/json";
            request.Accept = accept;
            request.Headers["Authorization"] = "Bearer " + token;
            byte[] bodyBytes = Encoding.UTF8.GetBytes(jsonBody);
            request.ContentLength = bodyBytes.Length;
            using (var s = request.GetRequestStream()) s.Write(bodyBytes, 0, bodyBytes.Length);

            using (var response = (HttpWebResponse)request.GetResponse())
            using (var ms = new MemoryStream())
            {
                response.GetResponseStream().CopyTo(ms);
                result = ms.ToArray();
                error = null;
                return true;
            }
        }
        catch (WebException wex)
        {
            string body = "";
            if (wex.Response != null)
                using (var sr = new StreamReader(wex.Response.GetResponseStream())) body = sr.ReadToEnd();
            error = wex.Message + " :: " + body;
            return false;
        }
        catch (Exception ex) { error = ex.Message; return false; }
    }

    private static double TileToLon(int x, int z) { return x / Math.Pow(2, z) * 360.0 - 180.0; }
    private static double TileToLat(int y, int z)
    {
        double n = Math.PI - 2.0 * Math.PI * y / Math.Pow(2, z);
        return 180.0 / Math.PI * Math.Atan(0.5 * (Math.Exp(n) - Math.Exp(-n)));
    }

    private static void WriteBytes(HttpResponse res, byte[] bytes, string contentType)
    {
        res.ContentType = contentType;
        res.Cache.SetCacheability(HttpCacheability.Public);
        res.Cache.SetMaxAge(TimeSpan.FromHours(6));
        res.OutputStream.Write(bytes, 0, bytes.Length);
    }

    // 1x1 saydam PNG — hata durumunda haritada kırık görsel ikonu göstermemek için
    private static readonly byte[] TransparentPng = Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

    private static void WriteError(HttpResponse res, bool debug, string message)
    {
        if (debug)
        {
            res.ContentType = "text/plain; charset=utf-8";
            res.StatusCode = 200;
            res.Write(message);
        }
        else
        {
            res.ContentType = "image/png";
            res.StatusCode = 200;
            res.OutputStream.Write(TransparentPng, 0, TransparentPng.Length);
        }
    }
}
