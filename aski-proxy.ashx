<%@ WebHandler Language="C#" Class="AskiProxy" %>
<%@ Assembly Name="System.Web.Extensions, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" %>

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;

// ═══════════════════════════════════════════════════════════════════════════
// ASKİ (Ankara Su ve Kanalizasyon İdaresi) — BARAJ DOLULUK ORANLARI PROXY
// ═══════════════════════════════════════════════════════════════════════════
// Kaynak: https://www.aski.gov.tr/tr/baraj.aspx — ASKİ'nin KENDİ resmi sayfası
// (üçüncü parti kazıma sitesi DEĞİL). O sayfa JSON API sunmuyor, düz HTML tablo
// döndürüyor; bu dosya sunucu tarafında o sayfayı çekip basit bir JSON'a çevirir.
//
// ÖNEMLİ — KAYNAK DOSYA KODLAMA SORUNU:
// Bu dosyadaki regex desenlerinde geçen ı/İ/ş/Ş/ğ/ü gibi Türkçe harfler BİLE
// İSTE \uXXXX unicode kaçış dizileriyle yazılıyor, düz karakter olarak DEĞİL.
// Sebep: canlı sunucuda (tr-TR IIS) tespit edildi — dosya UTF-8 BOM'suz
// kaydedilip yüklendiğinde, ASP.NET'in dinamik C# derleyicisi kaynak baytları
// sunucunun ANSI kod sayfasıyla (Windows-1254) okuyabiliyor ve kaynaktaki
// Türkçe harf LİTERALLERİ derleme anında yanlış karakterlere dönüşüyor —
// çalışma zamanında ağdan gelen (doğru UTF-8 çözülmüş) metinle asla
// eşleşmiyorlar. Kanıt: sabit "Akyar Barajı...Aktarım" test string'i bile
// regex'le eşleşmedi (_debugSelfTestLiteral:false), ama salt ASCII IndexOf
// aramaları ("Aktar", "Baraj Ad") doğru satırı buluyordu. \uXXXX kaçışları
// derleyicinin ASCII kaynak metnini nasıl okuduğundan bağımsız olduğu için
// bu sorunu kalıcı olarak ortadan kaldırır — dosya nasıl kaydedilirse
// kaydedilsin çalışır. YENİ regex deseni eklerken de bu kurala uyun.
// ═══════════════════════════════════════════════════════════════════════════

public class AskiProxy : IHttpHandler
{
    private const string ASKI_URL = "https://www.aski.gov.tr/tr/baraj.aspx";

    private static readonly TimeSpan CACHE_TTL = TimeSpan.FromHours(6);
    private static CacheEntry _cache;
    private static readonly object _lock = new object();

    private class CacheEntry { public string Json; public DateTime Expires; }

    public bool IsReusable { get { return true; } }

    public void ProcessRequest(HttpContext ctx)
    {
        try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { }

        var req = ctx.Request;
        var res = ctx.Response;
        bool debug = req.QueryString["debug"] == "1";
        string action = req.QueryString["action"] ?? "barajlar";

        try
        {
            string html;
            string err;
            if (!FetchHtml(out html, out err))
            {
                WriteJson(res, new JavaScriptSerializer().Serialize(new { ok = false, error = err }));
                return;
            }

            if (action == "raw")
            {
                // Geliştirme/ayar amaçlı: etiketleri temizlenmiş düz metni döner
                res.ContentType = "text/plain; charset=utf-8";
                res.Write(StripTags(html));
                return;
            }

            string json = BuildJson(html, debug);
            WriteJson(res, json);
        }
        catch (Exception ex)
        {
            WriteJson(res, new JavaScriptSerializer().Serialize(new { ok = false, error = "Sunucu hatası: " + ex.Message }));
        }
    }

    // ── Sayfayı çek (6 saatlik bellek-içi önbellek ile) ─────────────────────
    private static bool FetchHtml(out string html, out string error)
    {
        error = null;
        lock (_lock)
        {
            if (_cache != null && _cache.Expires > DateTime.UtcNow)
            {
                html = _cache.Json; // burada ham html'i saklıyoruz, isim yanıltıcı olmasın diye not
                return true;
            }
        }
        try
        {
            var wc = new WebClient();
            wc.Encoding = Encoding.UTF8;
            wc.Headers[HttpRequestHeader.UserAgent] = "Mozilla/5.0 (compatible; TarimsalCBS/1.0)";
            string raw = wc.DownloadString(ASKI_URL);
            lock (_lock) { _cache = new CacheEntry { Json = raw, Expires = DateTime.UtcNow.Add(CACHE_TTL) }; }
            html = raw;
            return true;
        }
        catch (Exception ex)
        {
            html = null;
            error = "ASKİ sayfası alınamadı: " + ex.Message;
            return false;
        }
    }

    // ── HTML → JSON ──────────────────────────────────────────────────────────
    private static string BuildJson(string html, bool debug)
    {
        string text = StripTags(html);
        var lines = new List<string>();
        foreach (var raw in text.Split('\n'))
        {
            var t = raw.Trim();
            if (t.Length > 0) lines.Add(t);
        }

        var result = new Dictionary<string, object>();
        result["ok"] = true;

        // ── Baraj satırları: "... Aktarım" içeren satır = baraj adı, onu takip
        // eden ilk 3 sayısal görünümlü satır = hacim / su miktarı / yüzde.
        var barajlar = new List<Dictionary<string, object>>();
        for (int i = 0; i < lines.Count; i++)
        {
            if (!Regex.IsMatch(lines[i], "Aktar[\u0131i]m", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) continue;
            if (!Regex.IsMatch(lines[i], "Baraj[\u0131i]?", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) continue;

            var nums = new List<double>();
            int j = i + 1;
            while (j < lines.Count && nums.Count < 3 && j < i + 8)
            {
                double val;
                // Sıra hep sabit: hacim, su miktarı (büyük tam sayı) → yüzde (0-100 ondalık).
                // ASKİ sitesi bazı hücrelerde TR (52.445.000 / 67,71), bazılarında ABD
                // (35,321,000 / 67.35) sayı biçimini karışık kullanabiliyor — bu yüzden
                // hacim/su miktarı için TÜM ayraçlar binlik sayılır, yüzde için TEK
                // ayraç (hangisi varsa) ondalık noktası sayılır.
                bool ok = nums.Count < 2 ? TryParseTrInteger(lines[j], out val) : TryParsePercent(lines[j], out val);
                if (ok) nums.Add(val);
                else if (Regex.IsMatch(lines[j], "Aktar[\u0131i]m", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) break; // sıradaki baraja geçmiş
                j++;
            }
            if (nums.Count == 3)
            {
                barajlar.Add(new Dictionary<string, object> {
                    { "ad", CleanBarajAdi(lines[i]) },
                    { "hacim", nums[0] },
                    { "suMiktari", nums[1] },
                    { "yuzde", nums[2] }
                });
            }
        }
        result["barajlar"] = barajlar;

        // ── Genel/toplam değerler: etiket satırını bul, ondan sonraki SON
        // sayısal değeri al (tabloda genelde [geçen yıl | bu yıl] iki sütun var,
        // en güncel sağdaki/sonuncu sütundur).
        result["toplamDolulukYuzde"] = FindLastNumberAfterLabel(lines, "Toplam Doluluk Y[u\u00FC]zdesi", true);
        result["aktifDolulukYuzde"]  = FindLastNumberAfterLabel(lines, "Aktif Kullan[\u0131i]labilir Su Y[u\u00FC]zdesi", true);
        result["suMiktari"]          = FindLastNumberAfterLabel(lines, "Barajlar[\u0131i]m[\u0131i]zdaki Su Miktar[\u0131i]");
        result["aktifSuMiktari"]     = FindLastNumberAfterLabel(lines, "Aktif Kullan[\u0131i]labilir Su Miktar[\u0131i]");
        result["sehreVerilenSu"]     = FindLastNumberAfterLabel(lines, "\u015Eehre Verilen Toplam Su Miktar[\u0131i]");
        result["tarih"]              = FindLastDateAfterLabel(lines, "^Tarih\\s*:?");

        if (debug)
        {
            result["_debugLineCount"] = lines.Count;
            result["_debugCulture"] = CultureInfo.CurrentCulture.Name + " / thread=" + System.Threading.Thread.CurrentThread.CurrentCulture.Name;
            // Sunucuda regex'in gerçekten eşleşip eşleşmediğini doğrudan görmek için:
            // hem sabit (literal) bir test string'ine, hem de sayfadan gerçekten
            // gelen ilk "Aktarım" içeren satıra karşı deniyoruz.
            const string sample = "Akyar Baraj\u0131 --> E\u011Frekkaya Baraj\u0131na Aktar\u0131m";
            result["_debugSelfTestLiteral"] = Regex.IsMatch(sample, "Aktar[\u0131i]m", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)
                && Regex.IsMatch(sample, "Baraj[\u0131i]?", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            string firstAktarimLine = null;
            foreach (var l in lines) { if (l.IndexOf("Aktar", StringComparison.OrdinalIgnoreCase) >= 0) { firstAktarimLine = l; break; } }
            result["_debugFirstAktarimLine"] = firstAktarimLine;
            result["_debugFirstAktarimLineMatchesRegex"] = firstAktarimLine != null
                && Regex.IsMatch(firstAktarimLine, "Aktar[\u0131i]m", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)
                && Regex.IsMatch(firstAktarimLine, "Baraj[\u0131i]?", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            // "Baraj Adı" tablo başlığından sonraki 8 satırı ham olarak dök —
            // gerçekten 10 baraj satırı mı geliyor, yoksa sayfa yapısı mı değişmiş.
            int hdrIdx = lines.FindIndex(l => l.IndexOf("Baraj Ad", StringComparison.OrdinalIgnoreCase) >= 0);
            var around = new List<string>();
            if (hdrIdx >= 0)
                for (int k = hdrIdx; k < lines.Count && k < hdrIdx + 12; k++) around.Add(lines[k]);
            result["_debugLinesAfterBarajAdiHeader"] = around;
        }
        return new JavaScriptSerializer().Serialize(result);
    }

    // Bir etiket satırından sonra gelen, en yakın 2 SATIRDAKİ (label + 2 sütun
    // değeri: geçen yıl / bu yıl) sayısal değerlerin SONUNCUSUNU döner (en
    // güncel/sağdaki sütun). Pencere kasıtlı olarak dar (i+3) tutuluyor —
    // geniş bir pencere (önceki sürümde i+5), sayfadaki bir sonraki etiketin
    // İLK veri satırını da yanlışlıkla yutup değeri bozuyordu (canlı sayfa
    // üzerinde doğrulandı).
    private static object FindLastNumberAfterLabel(List<string> lines, string labelPattern, bool isPercent = false)
    {
        for (int i = 0; i < lines.Count; i++)
        {
            if (!Regex.IsMatch(lines[i], labelPattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) continue;
            double last = double.NaN;
            for (int j = i; j < lines.Count && j < i + 3; j++)
            {
                double val;
                bool ok = isPercent ? TryParsePercent(lines[j], out val) : TryParseTrInteger(lines[j], out val);
                if (ok) last = val;
            }
            if (!double.IsNaN(last)) return last;
        }
        return null;
    }

    private static object FindLastDateAfterLabel(List<string> lines, string labelPattern)
    {
        for (int i = 0; i < lines.Count; i++)
        {
            if (!Regex.IsMatch(lines[i], labelPattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) continue;
            string last = null;
            for (int j = i; j < lines.Count && j < i + 3; j++)
            {
                var m = Regex.Match(lines[j], "\\d{1,2}\\.\\d{1,2}\\.\\d{4}");
                if (m.Success) last = m.Value;
            }
            if (last != null) return last;
        }
        return null;
    }

    private static string CleanBarajAdi(string line)
    {
        // "Çamlıdere Barajı --> İvedik Arıtma Tesisine Aktarım" → "Çamlıdere Barajı"
        var idx = line.IndexOf("-->");
        if (idx > 0) return line.Substring(0, idx).Trim();
        var m = Regex.Match(line, "^(.*?Baraj[\u0131i]?)\\b");
        return m.Success ? m.Groups[1].Value.Trim() : line.Trim();
    }

    // Büyük tam sayılar (hacim, su miktarı) için: ASKİ sitesi TR (52.445.000)
    // veya ABD (52,445,000) binlik ayracını karışık kullanabiliyor — ondalık
    // beklenmediğinden TÜM nokta/virgüller binlik ayraç sayılıp atılır.
    private static bool TryParseTrInteger(string s, out double val)
    {
        val = 0;
        if (string.IsNullOrWhiteSpace(s)) return false;
        s = s.Replace("%", "").Replace("m3", "").Replace("m³", "").Trim();
        if (!Regex.IsMatch(s, "^[\\d.,]+$")) return false;
        string digitsOnly = Regex.Replace(s, "[.,]", "");
        if (digitsOnly.Length == 0) return false;
        return double.TryParse(digitsOnly, NumberStyles.Integer, CultureInfo.InvariantCulture, out val);
    }

    // Yüzde gibi küçük ondalıklar için: TEK bir nokta/virgül ayracı (hangisi
    // varsa) ondalık noktası kabul edilir — TR "67,71" ve ABD "67.35"
    // biçimlerinin ikisini de doğru okur. Ayraç yoksa (örn. "100") tam sayıdır.
    private static bool TryParsePercent(string s, out double val)
    {
        val = 0;
        if (string.IsNullOrWhiteSpace(s)) return false;
        s = s.Replace("%", "").Trim();
        var m = Regex.Match(s, "^(\\d+)[.,](\\d{1,2})$");
        if (m.Success)
        {
            return double.TryParse(m.Groups[1].Value + "." + m.Groups[2].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out val);
        }
        if (Regex.IsMatch(s, "^\\d+$")) return double.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out val);
        return false;
    }

    private static string StripTags(string html)
    {
        string t = Regex.Replace(html, "<(script|style)[^>]*>[\\s\\S]*?</\\1>", " ", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        t = Regex.Replace(t, "<(br|tr|/tr|/td|/th|/p|/div|/table)[^>]*>", "\n", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        t = Regex.Replace(t, "<[^>]+>", "\n");
        t = HttpUtility.HtmlDecode(t);
        return t;
    }

    private static void WriteJson(HttpResponse res, string json)
    {
        res.ContentType = "application/json; charset=utf-8";
        res.Cache.SetCacheability(HttpCacheability.Public);
        res.Cache.SetMaxAge(TimeSpan.FromHours(1));
        res.Write(json);
    }
}
