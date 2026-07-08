/**
 * İçerik-adresli önbellek — AI-ANALIZ-TASARIMI.md §5.
 * inputHash = sha256(normalize(içerik) + tier + promptVersion + model)
 * Ayrı önbellek altyapısı YOK: aiAnalyses zaten sonuç deposu;
 * aynı hash'li belge = isabet → kota harcanmaz.
 */
import { createHash } from "node:crypto";

import type { Tier } from "./config.js";
import type { DecisionContent } from "./schema.js";

export function computeInputHash(params: {
  content: DecisionContent;
  tier: Tier;
  promptVersion: string;
  model: string;
}): string {
  const { content } = params;
  // Normalizasyon: alan sırası sabitlenir; id'ler dahil (perOption eşlemesi
  // id'ye bağlı), boşluk kırpılır. Anlam değiştirmeyen büyük/küçük harf
  // korunur (başlıkta anlam taşıyabilir).
  const normalized = {
    t: content.title.trim(),
    o: [...content.options]
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((o) => ({
        i: o.id,
        t: o.title.trim(),
        d: o.description?.trim() ?? "",
        p: o.pros.map((x) => x.trim()),
        c: o.cons.map((x) => x.trim()),
      })),
    c: [...content.criteria]
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((c) => ({ i: c.id, n: c.name.trim(), w: c.weight })),
    tier: params.tier,
    pv: params.promptVersion,
    m: params.model,
  };
  return createHash("sha256")
    .update(JSON.stringify(normalized))
    .digest("hex");
}
