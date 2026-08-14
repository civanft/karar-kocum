import { defineConfig } from "vitest/config";

// Hesap silme ENTEGRASYON testleri — Firestore + Auth emulator ZORUNLU.
// Çalıştırma: npm run test:privacy (emulators:exec sarmalayıcısıyla)
export default defineConfig({
  test: {
    include: ["test-privacy/**/*.test.ts"],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    // Tek dosya, tek Admin app: paralel çalıştırma emulator durumunu bozar.
    fileParallelism: false,
  },
});
