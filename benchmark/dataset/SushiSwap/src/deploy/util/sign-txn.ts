import { createSignWithKeypair } from "@kadena/client";
import { config } from "../config.js";

export const signTransaction = createSignWithKeypair({
	publicKey: config.pubKey,
	secretKey: config.secretKey,
});
