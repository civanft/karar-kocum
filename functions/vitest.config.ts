import { defineConfig } from "vitest/config";

// Varsayılan paket: yalnız birim testleri (emulator gerektirmez).
// Rules testleri ayrı config ile koşar: vitest.rules.config.ts
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
  },
});
