/**
 * Karar içeriği parmak izi (İş Paketi 2).
 *
 * AMAÇ: sağlayıcı çağrısı sürerken karar değişirse, eski içerik için üretilmiş
 * analiz YENİ karara bağlanmamalıdır. Parmak izi, AI girdisini etkileyen TÜM
 * alanları + model + promptVersion'ı kapsar; kanonik ve deterministiktir.
 *
 * Journal'a ham karar metni YAZILMAZ; yalnız bu özet tutulur.
 */
import { createHash } from "node:crypto";

import type { DecisionContent } from "./schema.js";

/**
 * Kanonik serileştirme: alan sırası SABİT, dizilerin sırası korunur
 * (sıra AI girdisini etkiler), boş/nullish alanlar normalize edilir.
 */
function canonical(content: DecisionContent): string {
  return JSON.stringify({
    title: content.title,
    options: content.options.map((o) => ({
      id: o.id,
      title: o.title,
      description: o.description ?? "",
      pros: o.pros,
      cons: o.cons,
    })),
    criteria: content.criteria.map((c) => ({
      id: c.id,
      name: c.name,
      weight: c.weight,
    })),
  });
}

export function contentFingerprint(params: {
  content: DecisionContent;
  model: string;
  promptVersion: string;
}): string {
  const payload = JSON.stringify({
    v: 1,
    model: params.model,
    promptVersion: params.promptVersion,
    content: canonical(params.content),
  });
  return createHash("sha256").update(payload).digest("hex");
}
