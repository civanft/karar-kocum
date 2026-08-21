/**
 * Secret Manager bağları.
 * Değerler koda/env dosyasına yazılmaz; deploy'da fonksiyona bağlanır:
 *   npx firebase-tools functions:secrets:set OPENAI_API_KEY
 * Erişim yalnız secrets listesinde bu bağı bildiren fonksiyonlarda,
 * çalışma zamanında openaiApiKey.value() ile.
 */
import { defineSecret } from "firebase-functions/params";

export const openaiApiKey = defineSecret("OPENAI_API_KEY");

// NOT: RevenueCat webhook sırrı burada TANIMLANMAZ. defineSecret yalnız
// gerçekten bağlanacağı fonksiyonla birlikte eklenir (Sprint 5); kullanılmayan
// bir bağ, deploy yüzeyinde gereksiz secret erişimi ister.
