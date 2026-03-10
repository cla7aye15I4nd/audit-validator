# Transaction handler signature verification only checks `signature` field, ignoring `signatures` array


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `2e0c71e0-9311-11f0-8617-07932f2b3ecc` |
| Commit | `164644735399110e14ad54c0db3f50ebfad78a63` |

## Location

- **Local path:** `./source_code/github/GalaChain/sdk/164644735399110e14ad54c0db3f50ebfad78a63/chaincode/src/contracts/GalaTransaction.ts`
- **ACC link:** https://acc.audit.certikpowered.info/project/2e0c71e0-9311-11f0-8617-07932f2b3ecc/source?file=$/github/GalaChain/sdk/164644735399110e14ad54c0db3f50ebfad78a63/chaincode/src/contracts/GalaTransaction.ts
- **Lines:** 196–197

## Description

The transaction handler's signature verification logic only checks for the presence of the `signature` field but ignores the `signatures` array used for multisignature DTOs, potentially bypassing authentication for multisignature operations.

```typescript
} else if (options?.verifySignature || dto?.signature !== undefined) {
  ctx.callingUserData = await authenticate(ctx, dto);
```

The current implementation creates a security gap where:
- Single signature DTOs are properly authenticated via `authenticate()`
- Multisignature DTOs (with `signatures` array but no `signature` field) bypass authentication entirely
- This could allow unauthorized access to operations that should require multisignature verification

The logic incorrectly assumes that if `dto.signature` is undefined, no signature verification is needed, failing to account for the multisignature case.

## Recommendation

Update the signature verification condition to check for both signature fields:

```typescript
} else if (options?.verifySignature || dto?.signature !== undefined || dto?.signatures?.length > 0) {
  ctx.callingUserData = await authenticate(ctx, dto);
```

Ensure the `authenticate()` function properly handles both single signature and multisignature DTOs to maintain consistent security validation across all signature types.

## Vulnerable Code

```
if (method?.name === undefined) {
      throw new RuntimeError("Undefined method name for descriptor.value: " + inspect(method));
    }

    const loggingContext = `${className}:${method.name ?? "UnknownMethod"}`;

    // Creates the new method. The first parameter is always ctx, the second,
    // optional one, is a plain dto object. We ignore the rest. This is our
    // convention.
    // eslint-disable-next-line no-param-reassign
    descriptor.value = async function (ctx, dtoPlain) {
      try {
        const metadata = [{ dto: dtoPlain }];
        ctx?.logger?.logTimeline("Begin Transaction", loggingContext, metadata);

        // Parse & validate - may throw an exception
        const dtoClass = options.in ?? (ChainCallDTO as unknown as ClassConstructor<Inferred<In>>);
        const dto = !dtoPlain
          ? undefined
          : await parseValidDTO<In>(dtoClass, dtoPlain as string | Record<string, unknown>);

        // Note using Date.now() instead of ctx.txUnixTime which is provided client-side.
        if (dto?.dtoExpiresAt && dto.dtoExpiresAt < Date.now()) {
          throw new ExpiredError(`DTO expired at ${new Date(dto.dtoExpiresAt).toISOString()}`);
        }

        // Authenticate the user
        if (ctx.isDryRun) {
          // Do not authenticate in dry run mode
        } else if (options?.verifySignature || dto?.signature !== undefined) {
          ctx.callingUserData = await authenticate(ctx, dto);
        } else {
          // it means a request where authorization is not required. If there is org-based authorization,
          // default roles are applied. If not, then only evaluate is possible. Alias is intentionally
          // missing.
          const roles = !options.allowedOrgs?.length ? [UserRole.EVALUATE] : [...UserProfile.DEFAULT_ROLES];
          ctx.callingUserData = { roles, signatureQuorum: 0, signedByKeys: [] };
        }

        // Authorize the user
        await authorize(ctx, options);

        // Prevent the same transaction from being submitted multiple times
        if (options.enforceUniqueKey) {
          if (dto?.uniqueKey) {
            await UniqueTransactionService.ensureUniqueTransaction(ctx, dto.uniqueKey);
          } else {
            const message = `Missing uniqueKey in transaction dto for method '${method.name}'`;
            throw new RuntimeError(message);
          }
        }

        const argArray: [GalaChainContext, In] | [GalaChainContext] = dto ? [ctx, dto] : [ctx];

        if (options?.before !== undefined) {
          await options?.before?.apply(this, argArray);
        }

        // Execute the method. Note the contract method is always an async
        // function, so it is safe to do the `await`
        const result = await method?.apply(this, argArray);
```
