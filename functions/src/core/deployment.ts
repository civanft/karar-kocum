/**
 * Deploy hedefi ↔ çalışma bölgesi (PR-PROD-2).
 *
 * Bölge deploy ZAMANINDA `projectID` parametresinden çözülür. Global
 * scope'ta `process.env` OKUNMAZ: analiz/emulator aşamasında env yoktur ve
 * `FUNCTION_REGION` çalışma zamanı için ayrılmış (reserved) bir addır.
 *
 * Production Firestore `eur3` bölgesinde kurulacağı için fonksiyonlar
 * `europe-west1`'e yerleşir — aynı kıtada kalmak Firestore gidiş-dönüş
 * gecikmesini ve kıtalar arası çıkış trafiğini azaltır. Mevcut dev
 * fonksiyonlarının konumu (`us-central1`) DEĞİŞMEZ; Cloud Functions'ta bir
 * fonksiyonun bölgesi yerinde değiştirilemez, bu yüzden dev yüzeyi olduğu
 * gibi kalır.
 */
import { projectID } from "firebase-functions/params";

export const DEV_PROJECT_ID = "karar-veriyorum-dev";
export const PROD_PROJECT_ID = "karar-kocum-production";

export const DEV_REGION = "us-central1";
export const PROD_REGION = "europe-west1";

/**
 * Saf eşleme (test seam'i). Tanınmayan proje güvenli tarafa — dev
 * bölgesine — düşer: yanlışlıkla açılan bir sandbox projesi, production
 * bölgesini sahiplenmiş gibi görünmemelidir.
 */
export function regionForProject(projectId: string): string {
  return projectId === PROD_PROJECT_ID ? PROD_REGION : DEV_REGION;
}

/**
 * Deploy-zamanı bölge ifadesi — dört export'un TAMAMI bunu kullanır.
 * Sabitin fonksiyon dosyalarına kopyalanması, tek bir dosyanın geride
 * kalmasıyla yüzeyin bölünmesine yol açar.
 */
export const functionRegion = projectID
  .equals(PROD_PROJECT_ID)
  .thenElse(PROD_REGION, DEV_REGION);
