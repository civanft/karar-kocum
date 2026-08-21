import assert from "node:assert/strict";
import test from "node:test";

import { readSmokeFirebaseConfig } from "./firebase_config.mjs";

test("anahtar ortamda yoksa AĞ İSTEĞİ OLMADAN durur", () => {
  assert.throws(() => readSmokeFirebaseConfig({}), /FIREBASE_WEB_API_KEY/);
});

test("boş/boşluklu değer de eksik sayılır", () => {
  assert.throws(
    () => readSmokeFirebaseConfig({ FIREBASE_WEB_API_KEY: "   " }),
    /FIREBASE_WEB_API_KEY/,
  );
});

test("anahtar YALNIZ ortamdan alınır", () => {
  const config = readSmokeFirebaseConfig({
    FIREBASE_WEB_API_KEY: "test-client-key-from-environment",
  });

  assert.equal(config.apiKey, "test-client-key-from-environment");
  assert.equal(config.projectId, "karar-veriyorum-dev");
  assert.equal(config.appId, "1:740423241326:android:9faaa1a25d96871d04a07f");
});

test("hata mesajı secret DEĞERİ içermez", () => {
  // Yanlışlıkla set edilmiş ama geçersiz (boşluk) bir değer bile mesaja
  // sızmamalı; mesaj yalnız değişken ADINI anmalı.
  // Sentinel bilinçli olarak GERÇEK anahtar biçimine benzemez: sahte bile olsa
  // anahtar biçimli dize, gelecekteki secret taramalarında yanlış alarm üretir.
  const sentinel = "SENTINEL-do-not-leak-this-value-0123456789";
  try {
    readSmokeFirebaseConfig({ FIREBASE_WEB_API_KEY: `  ` , OTHER: sentinel });
    assert.fail("hata bekleniyordu");
  } catch (error) {
    assert.ok(!String(error.message).includes(sentinel));
    assert.ok(!/AIza/.test(String(error.message)));
  }
});

test("kaynak dosyada sabit kodlanmış istemci anahtarı yok", async () => {
  const source = await (await import("node:fs/promises")).readFile(
    new URL("./firebase_config.mjs", import.meta.url),
    "utf8",
  );
  assert.ok(!/AIza[0-9A-Za-z_-]{35}/.test(source));
});
