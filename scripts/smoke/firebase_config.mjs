export function readSmokeFirebaseConfig(env = process.env) {
  const apiKey = env.FIREBASE_SMOKE_API_KEY?.trim();
  if (!apiKey) {
    throw new Error(
      "FIREBASE_SMOKE_API_KEY ortam değişkeni gerekli; istemci anahtarını repoya yazmayın.",
    );
  }

  return {
    apiKey,
    appId: "1:740423241326:android:9faaa1a25d96871d04a07f",
    messagingSenderId: "740423241326",
    projectId: "karar-veriyorum-dev",
  };
}
