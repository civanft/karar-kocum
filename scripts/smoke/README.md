# Canlı Firebase smoke testi

İstemci Firebase API anahtarı repoya tekrar yazılmaz. Kök `.env.example`
dosyasını `.env` olarak kopyalayıp yerel geliştirme anahtarını özel olarak girin;
`chmod 600 .env` uygulayın. `.env` Git tarafından yok sayılır.

```bash
cd scripts/smoke
npm ci
node --env-file=../../.env live_smoke_test.mjs
```

Anahtar komut çıktısına yazdırılmaz ve shell profiline kaydedilmez. Firebase
istemci anahtarları public tanımlayıcı olsa da yalnız Firebase API allowlist'i
ile kullanılmalı; OpenAI ve diğer sunucu sırları daima Secret Manager'da kalır.

Bu test DEV projesinde kullanıcı/veri oluşturur; production testi değildir.
