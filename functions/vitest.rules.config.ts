import { defineConfig } from "vitest/config";

// Firestore RULES testleri — emulator ZORUNLU.
// Çalıştırma: npm run test:rules (emulators:exec sarmalayıcısıyla)
export default defineConfig({
  test: {
    include: ["test-rules/**/*.test.ts"],
    testTimeout: 20_000,
    hookTimeout: 30_000,
  },
});
