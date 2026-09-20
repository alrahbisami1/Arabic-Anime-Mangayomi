# Arabic-Anime-Mangayomi

مستودع امتدادات **Mangayomi** لمصادر الأنمي العربية (كتابة Dart) يعمل على **iOS** و**Android**.

> هذا ريبو مستقل عن ريبو CloudStream. صُممت الامتدادات من الصفر لتوافق واجهة Mangayomi.

## المحتوى

| الامتداد | الموقع | الجودة | ملاحظات |
|---|---|---|---|
| Anime3rb | https://anime3rb.com | 1080p / 1080p HEVC / 720p / 480p | بحث عبر خريطة المواقع |
| AnimePhoenix | https://anime-phoenix.com | 1080p | سيرفرات مشاهدة/تحميل متعددة |
| WitAnime | https://witanime.you | 1080p | ⚠️ خلف Cloudflare — قد تفشل الطلبات أحيانًا |
| Anime4up | https://w1.anime4up.rest | FHD / HD / SD / LD | فلاتر جودة + خوادم متعددة |

## طريقة التثبيت (iOS و Android)

1. ثبّت تطبيق **Mangayomi** على الآيفون من النسخة الرسمية:
   https://github.com/kodjodevf/mangayomi/releases

2. ارفع هذا المستودع إلى GitHub (إن لم يكن مرفوعًا).

3. في التطبيق: **More → Settings → Browse → Anime extensions repo → Add** ثم أدخل الرابط:

   ```
   https://raw.githubusercontent.com/alrahbisami1/Arabic-Anime-Mangayomi/main/anime_index.json
   ```

4. افتح Now → Anime وستجد الامتدادات الأربعة، اضغط تثبيت بجانبها.

> بديل: عند تثبيت Mangayomi لأول مرة يمكنك إضافة الريبو الرسمي ثم هذا الريبو وكلاهما سيعمل معًا.

## هيكل الملفات

```
Arabic-Anime-Mangayomi/
├── anime_index.json              # فهرس امتدادات الأنمي (يُقرأ من قبل Mangayomi)
├── README.md
└── dart/anime/ar/
    ├── anime3rb/anime3rb.dart
    ├── animephoenix/animephoenix.dart
    ├── witanime/witanime.dart
    └── anime4up/anime4up.dart
```

`anime_index.json` هو الملف الذي يقرؤه Mangayomi عند إضافة الريبو — أي تعديل (تغيير ID أو عنوان أو رابط) يجب أن يتم فيه فقط.

## ملاحظات تقنية

- الامتدادات تستخدم محللات Mangayomi المدمجة (`doodExtractor`, `voeExtractor`, `mp4UploadExtractor`, `vidBomExtractor`, `streamTapeExtractor`, `filemoonExtractor`, `streamWishExtractor`, `sendVidExtractor`, `yourUploadExtractor`, `okruExtractor`) مع fallback مباشر لروابط `m3u8/mp4`.
- ترتيب الفيديوهات تنازلي حسب الجودة (يظهر أفضل جودة أولًا).
- `hasCloudflare: true` لـ WitAnime وAnime4up فقط؛ المواقع الأخرى تفتح مباشرة.

## روابط مفيدة

- مصدر تثبيت Mangayomi الرسمي: https://raw.githubusercontent.com/kodjodevf/mangayomi/releases
