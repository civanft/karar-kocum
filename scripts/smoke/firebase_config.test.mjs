import assert from "node:assert/strict";
import test from "node:test";

import { readSmokeFirebaseConfig } from "./firebase_config.mjs";

test("smoke Firebase anahtarı ortamda yoksa güvenli biçimde durur", () => {
  assert.throws(
    () => readSmokeFirebaseConfig({}),
    /FIREBASE_SMOKE_API_KEY/,
  );
});

test("smoke Firebase yapılandırması anahtarı yalnız ortamdan alır", () => {
  const config = readSmokeFirebaseConfig({
    FIREBASE_SMOKE_API_KEY: "test-client-key-from-environment",
  });

  assert.equal(config.apiKey, "test-client-key-from-environment");
  assert.equal(config.projectId, "karar-veriyorum-dev");
  assert.equal(config.appId, "1:740423241326:android:9faaa1a25d96871d04a07f");
});
