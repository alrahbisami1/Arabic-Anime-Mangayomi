# Arabic-Anime-Mangayomi

مستودع امتدادات **Mangayomi** لمصادر الأنمي العربية (كتابة Dart) يعمل على **iOS** و**Android**.

> هذا ريبو مستقل عن ريبو CloudStream. صُممت الامتدادات من الصفر لتوافق واجهة Mangayomi.

## المحتوى

| الامتداد | الموقع | الجودة | ملاحظات |
|---|---|---|---|
| Anime3rb | https://anime3rb.com | 1080p / 1080p HEVC / 720p / 480p | بحث عبر خريطة المواقع |
| Animerco | https://eta.animerco.org | 1080p | ⚠️ خلف Cloudflare — قد تفشل الطلبات أحيانًا |
| AnimePhoenix | https://anime-phoenix.com | 1080p | سيرفرات مشاهدة/تحميل متعددة |
| Animedar | https://animedar.net | FHD / HD / SD / LD | فلاتر جودة + خوادم متعددة |

## طريقة التثبيت (iOS و Android)

1. **ثبّت تطبيق Mangayomi** على الآيفون من النسخة الرسمية:
   https://github.com/kodjodevf/mangayomi/releases

2. **ارفع هذا المستودع إلى GitHub** ثم فعّل **GitHub Pages** من:
   `Settings → Pages → Source: Deploy from a branch → main (root)`.

3. في التطبيق: **More → Settings → Browse → Anime extensions repo → Add** ثم أدخل الرابط:

   ```
   https://alrahbisami1.github.io/Arabic-Anime-Mangayomi/
   ```

4. افتح Now → Anime وستجد الامتدادات الأربعة، اضغط تثبيت بجانبها.

> بديل: عند تثبيت Mangayomi لأول مرة يمكنك إضافة الريبو الرسمي ثم هذا الريبو وكلاهما سيعمل معًا.

## هيكل الملفات

```
Arabic-Anime-Mangayomi/
├── anime_index.json              # فهرس امتدادات الأنمي (المطلوب لتظهر في التطبيق)
└── dart/anime/ar/
    ├── anime3rb/anime3rb.dart
    ├── animerco/animerco.dart
    ├── animephoenix/animephoenix.dart
    └── animedar/animedar.dart
```

`anime_index.json` هو الملف الذي يقرأه Mangayomi عند إضافة الريبو — أي تعديل (تغيير ID أو عنوان أو رابط) يجب أن يتم فيه فقط.

## ملاحظات تقنية

- الامتدادات تستخدم محللات Mangayomi المدمجة (`doodExtractor`, `voeExtractor`, `mp4UploadExtractor`, `vidBomExtractor`, `streamTapeExtractor`, `filemoonExtractor`, `streamWishExtractor`, `sendVidExtractor`, `yourUploadExtractor`, `okruExtractor`) مع fallback مباشر لروابط `m3u8/mp4`.
- ترتيب الفيديوات تنازلي حسب الجودة (يظهر أفضل جودة أولًا).
- `hasCloudflare: true` لـ Animerco فقط؛ المواقع الأخرى تفتح مباشرة.

## روابط مفيدة

- مصدر تثبيت Mangayomi الرسمي: https://raw.githubusercontent.com/kodjodevf/mangayomi/refs/heads/main/repo/source.json
- نموذج ريبو امتدادات مرجعي: https://m2k3a.github.io/mangayomi-extensions/anime_index.json