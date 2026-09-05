/**
 * İŞ PAKETİ 2D — rezervasyon tahmini GERÇEK bir ÜST SINIR olmalıdır.
 *
 * 2B/2C'de `ceil(promptChars / 3)` kullanılıyordu ve "konservatif üst sınır"
 * gibi davranılıyordu. Bu iddia YANLIŞTIR: karakter sayısı ile token sayısı
 * arasında böyle bir alt/üst ilişki yoktur. Emoji, birleşik Unicode, CJK ve
 * tekrarlı çok baytlı karakterlerde tahmin gerçek token sayısının ALTINDA
 * kalır — yani bütçe kontrolü delinebilir.
 *
 * Bu testler gerçek `o200k_base` tokenizer'ına (js-tiktoken, YALNIZ
 * devDependency) karşı koşar. Üretim kodu tokenizer İÇERMEZ; üretimde
 * matematiksel olarak kanıtlanabilir bir UTF-8 bayt üst sınırı kullanılır.
 */
import { getEncoding } from "js-tiktoken";
import { describe, expect, it } from "vitest";

import {
  estimateUsage,
  utf8UpperBoundTokens,
  FRAMING_TOKENS_PER_MESSAGE,
  FRAMING_TOKENS_OVERHEAD,
} from "../src/ai/usage_estimate";
import { AppError } from "../src/core/errors";

/**
 * gpt-4.1-mini `o200k_base` kullanır. Bu testler tokenizer'ı yalnız GERÇEK
 * token sayısını ölçmek için kullanır; üst sınır iddiası tokenizer'ın
 * kimliğine DEĞİL, byte-level BPE'nin yapısal özelliğine dayanır.
 */
const enc = getEncoding("o200k_base");
const realTokens = (s: string) => enc.encode(s).length;

/** Tokenizer'ı zorlayan gerçekçi örnekler. */
const CORPUS: Record<string, string> = {
  turkce:
    "Yeni bir telefon almalı mıyım, yoksa mevcut cihazımı bir yıl daha " +
    "kullanmalı mıyım? Bütçem sınırlı ve kamera kalitesi benim için önemli.",
  emoji: "👨‍👩‍👧‍👦🇹🇷🏳️‍🌈👍🏽😀😀😀",
  birlesikUnicode: "ééé güneş çiçek ağaç",
  cjk: "私は新しい電話を買うべきですか。予算は限られています。",
  ascii: "Should I buy a new phone or keep the current one for another year?",
  tekrarliCokBaytli: "ı".repeat(300),
  bosluklu: "   \n\n\t   ",
  bos: "",
};

describe("eski tahmin (chars/3) ÜST SINIR DEĞİLDİR", () => {
  const eskiTahmin = (s: string) => Math.ceil(s.length / 3);

  it("en az bir gerçekçi girdide gerçek token sayısının ALTINDA kalır", () => {
    const altinda = Object.entries(CORPUS).filter(
      ([, text]) => eskiTahmin(text) < realTokens(text),
    );
    expect(altinda.length).toBeGreaterThan(0);
  });

  it.each([
    ["emoji", CORPUS.emoji!],
    ["birlesikUnicode", CORPUS.birlesikUnicode!],
    ["cjk", CORPUS.cjk!],
    ["tekrarliCokBaytli", CORPUS.tekrarliCokBaytli!],
  ])("%s: chars/3 gerçek token sayısını AŞAĞI kaçırır", (_ad, text) => {
    expect(eskiTahmin(text)).toBeLessThan(realTokens(text));
  });
});

describe("yeni üst sınır: UTF-8 bayt sayısı", () => {
  /**
   * KANIT: byte-level BPE'de her token en az BİR bayta çözülür ve tokenlerin
   * bayt çözümleri girdiyi tam olarak parçalar. Dolayısıyla
   * token_sayısı ≤ bayt_sayısı — HER byte-level BPE kodlaması için.
   * Bu, kodlamanın kimliğinden bağımsızdır.
   */
  it.each(Object.entries(CORPUS))(
    "%s: bayt üst sınırı gerçek token sayısının ALTINDA KALMAZ",
    (_ad, text) => {
      expect(utf8UpperBoundTokens(text)).toBeGreaterThanOrEqual(
        realTokens(text),
      );
    },
  );

  it("property: rastgele Unicode dizilerinde de altında kalmaz", () => {
    const rnd = (n: number) =>
      Array.from({ length: n }, () =>
        String.fromCodePoint(
          [0x41, 0x131, 0x11f, 0x4e2d, 0x1f600, 0x0301, 0x20][
            Math.floor(Math.random() * 7)
          ]!,
        ),
      ).join("");

    for (let i = 0; i < 200; i++) {
      const text = rnd(1 + Math.floor(Math.random() * 60));
      expect(utf8UpperBoundTokens(text)).toBeGreaterThanOrEqual(
        realTokens(text),
      );
    }
  });
});

describe("estimateUsage sözleşmesi", () => {
  const base = {
    systemPrompt: CORPUS.turkce!,
    userPrompt: CORPUS.cjk!,
    maxOutputTokens: 800,
    model: "gpt-4.1-mini",
  };

  it("system + user + framing + max output tokens'ın TAMAMINI kapsar", () => {
    const e = estimateUsage(base);
    const icerik =
      utf8UpperBoundTokens(base.systemPrompt) +
      utf8UpperBoundTokens(base.userPrompt);
    const framing = 2 * FRAMING_TOKENS_PER_MESSAGE + FRAMING_TOKENS_OVERHEAD;
    expect(e.tokens).toBe(icerik + framing + base.maxOutputTokens);
  });

  it("system prompt'u ATLAMAZ", () => {
    const ile = estimateUsage(base);
    const olmadan = estimateUsage({ ...base, systemPrompt: "" });
    expect(ile.tokens).toBeGreaterThan(olmadan.tokens);
  });

  it("max output tokens'ı ATLAMAZ", () => {
    const buyuk = estimateUsage({ ...base, maxOutputTokens: 4000 });
    expect(buyuk.tokens - estimateUsage(base).tokens).toBe(4000 - 800);
  });

  it("USD giriş ve çıkış fiyatlarını AYRI hesaplar", () => {
    // Çıkış tokeni girişten pahalıdır (1.60 vs 0.40 / 1M). Yalnız çıkışı
    // artırmak, aynı miktarda girişi artırmaktan DAHA ÇOK maliyet üretmeli.
    const cikis = estimateUsage({ ...base, maxOutputTokens: 800 + 1000 });
    const giris = estimateUsage({
      ...base,
      userPrompt: base.userPrompt + "a".repeat(1000),
    });
    expect(cikis.usd - estimateUsage(base).usd).toBeGreaterThan(
      giris.usd - estimateUsage(base).usd,
    );
  });

  it("gerçek kullanımın ALTINDA kalmaz (uçtan uca)", () => {
    const e = estimateUsage(base);
    const gercekGiris =
      realTokens(base.systemPrompt) + realTokens(base.userPrompt);
    expect(e.tokens).toBeGreaterThanOrEqual(gercekGiris + base.maxOutputTokens);
  });
});

describe("güvenli sayısal sınırlar", () => {
  const base = {
    systemPrompt: "a",
    userPrompt: "b",
    maxOutputTokens: 800,
    model: "gpt-4.1-mini",
  };

  it.each([NaN, -1, Infinity, 1.5])(
    "geçersiz maxOutputTokens (%s) REDDEDİLİR",
    (bad) => {
      expect(() =>
        estimateUsage({ ...base, maxOutputTokens: bad as number }),
      ).toThrow(AppError);
    },
  );

  it("aşırı büyük girdi REDDEDİLİR (taşma yok)", () => {
    expect(() =>
      estimateUsage({ ...base, maxOutputTokens: Number.MAX_SAFE_INTEGER }),
    ).toThrow(AppError);
  });

  it("sonuç daima pozitif tamsayıdır", () => {
    const e = estimateUsage({ ...base, systemPrompt: "", userPrompt: "" });
    expect(Number.isSafeInteger(e.tokens)).toBe(true);
    expect(e.tokens).toBeGreaterThan(0);
    expect(Number.isFinite(e.usd)).toBe(true);
    expect(e.usd).toBeGreaterThan(0);
  });
});
