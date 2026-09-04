import { defineConfig } from "vitest/config";

// Journal idempotency ENTEGRASYON testleri — Firestore emulator ZORUNLU.
// Çalıştırma: npm run test:emulator (emulators:exec sarmalayıcısıyla)
export default defineConfig({
  test: {
    include: ["test-emulator/**/*.test.ts"],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    // Tek Admin app + paylaşılan emulator durumu: paralel dosya YOK.
    fileParallelism: false,
  },
});
