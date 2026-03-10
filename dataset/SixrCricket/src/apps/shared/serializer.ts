/**
 * @file serializer.ts
 * @notice JSON serialization utilities for safe BigInt handling
 *
 * This module provides utilities to serialize objects containing BigInt values
 * to JSON-safe formats. BigInt values cannot be serialized by JSON.stringify()
 * and will cause runtime errors if not converted to strings first.
 */

import { PayloadWithSignatures } from './types';

/**
 * Deep converts all BigInt values in an object to strings
 * Handles nested objects and arrays recursively
 *
 * @param obj - Any value to convert
 * @returns Object with all BigInt values converted to strings
 */
export function serializeBigInt<T>(obj: T): T {
  if (obj === null || obj === undefined) {
    return obj;
  }

  // Handle BigInt primitives
  if (typeof obj === 'bigint') {
    return String(obj) as T;
  }

  // Handle arrays
  if (Array.isArray(obj)) {
    return obj.map((item) => serializeBigInt(item)) as T;
  }

  // Handle objects
  if (typeof obj === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj)) {
      result[key] = serializeBigInt(value);
    }
    return result as T;
  }

  // Primitive types (string, number, boolean)
  return obj;
}

/**
 * Serializes a PayloadWithSignatures object for JSON responses
 * Ensures all BigInt fields (nonce, burnLt, tonMintLt, tonMintAttempts) are strings
 *
 * @param payload - Payload with signatures
 * @returns JSON-safe payload object
 */
export function toJsonPayload(
  payload: PayloadWithSignatures
): PayloadWithSignatures {
  // The PayloadWithSignatures type already has BigInt fields as strings,
  // but we apply deep serialization to be extra safe and handle any
  // edge cases where BigInt might slip through
  return serializeBigInt(payload);
}

/**
 * Serializes an array of PayloadWithSignatures objects for JSON responses
 *
 * @param payloads - Array of payloads with signatures
 * @returns JSON-safe array of payload objects
 */
export function toJsonPayloads(
  payloads: PayloadWithSignatures[]
): PayloadWithSignatures[] {
  return payloads.map(toJsonPayload);
}

/**
 * Serializes any object for JSON responses, converting all BigInt values to strings
 * Use this for ad-hoc responses that may contain BigInt values
 *
 * @param data - Any data to serialize
 * @returns JSON-safe data
 */
export function toJsonSafe<T>(data: T): T {
  return serializeBigInt(data);
}
