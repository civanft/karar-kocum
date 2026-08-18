# Canlı Firebase smoke testi

İstemci Firebase API anahtarı repoya tekrar yazılmaz. Test, ignore edilen
`android/app/google-services.json` dosyasından anahtarı süreç ortamına alır:

```bash
cd scripts/smoke
npm ci
FIREBASE_SMOKE_API_KEY="$(jq -r '.client[0].api_key[0].current_key' ../../android/app/google-services.json)" npm run smoke
```

Anahtar komut çıktısına yazdırılmaz ve shell profiline kaydedilmez. Firebase
istemci anahtarları public tanımlayıcı olsa da yalnız Firebase API allowlist'i
ile kullanılmalı; OpenAI ve diğer sunucu sırları daima Secret Manager'da kalır.
