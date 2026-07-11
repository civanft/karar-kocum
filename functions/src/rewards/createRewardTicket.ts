/**
 * Ödül bileti callable'ı — reklam gösteriminden ÖNCE çağrılır.
 * Dönen ticketId, AdMob SSV custom_data'sına konur; ödülü callback verir.
 */
import { onCall } from "firebase-functions/v2/https";

import { toHttpsError } from "../core/errors.js";
import { log } from "../core/logger.js";
import { buildContext } from "../middleware/context.js";
import {
  FirestoreRateLimitStore,
  RateLimiter,
} from "../quota/rate_limiter.js";
import {
  createRewardTicket as createTicket,
  FirestoreTicketStore,
} from "./reward_service.js";
import { REWARD_TICKET_LIMITS } from "../config.js";

const limiter = () =>
  new RateLimiter(new FirestoreRateLimitStore(), REWARD_TICKET_LIMITS);

export const createRewardTicket = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (request) => {
    const ctx = buildContext("createRewardTicket", request);
    try {
      // Analiz limitiyle çakışmasın diye ayrı anahtar alanı:
      await limiter().check(`${ctx.uid}:reward`);
      const ticket = await createTicket(new FirestoreTicketStore(), ctx.uid);
      log("info", "reward_ticket_created", ctx, {
        ticketId: ticket.ticketId,
      });
      return ticket;
    } catch (error) {
      throw toHttpsError(error, ctx);
    }
  },
);
