# Underconstrained Circuit `BitsToBytes` Allows Arbitrary SHA256 Hash


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `7c846b50-3220-11ef-89f8-c16e900c7ea1` |
| Commit | `ee1a9ee620dae6e1d68d95f7d0d626fd5930cfdb` |

## Location

- **Local path:** `./src/circuits/helpers/utils.circom`
- **ACC link:** https://acc.audit.certikpowered.info/project/7c846b50-3220-11ef-89f8-c16e900c7ea1/source?file=$/github/Portkey-Wallet/zkLogin-circuit/ee1a9ee620dae6e1d68d95f7d0d626fd5930cfdb/circuits/helpers/utils.circom
- **Lines:** 232–232

## Description

The circuit `BitsToBytes` is meant to turn an array of bits into an array of bytes. However, there are no constraints involved, allowing the output to have elements greater than 8 bits, or even elements that have no connection with the original input array.

```circom
template BitsToBytes(bits){
  signal input in[bits];
  signal output out[bits/8];
  for (var i=0; i<bits/8; i++) {
    var bytevalue = 0;
    for (var j=0; j<8; j++) {
      bytevalue |= in[i * 8 + j] ? (1 << (7-j)) : 0;
    }
    out[i] <-- bytevalue;
  }
```

This means that regardless of the input array, the output array can hold any values. This circuit is used in the main circuits `ZkLoginSha256` and `IdHashMapping`, which do not have further checks on the output. 

This is dangerous as the output is meant to be a specific SHA256 hash, but an attacker would be able to choose an arbitrary hash to use.

## Recommendation

It is recommended to constrain the output properly. A possible solution is to use the `Bits2Num(8)` circuit in circomlib to turn each 8 bits of `in` to a byte.

## Vulnerable Code

```
blinder_matches <== intermediate_is_message_id_from[blinder_len];
    anon_salt <== hasher.outs[0];
}


template CombineBytes(first_bytes, second_bytes) {
  // inputs
  signal input first[first_bytes];
  signal input second[second_bytes];

  signal output out[first_bytes + second_bytes];

  for (var i = 0; i < first_bytes; i++) {
      out[i] <== first[i];
  }

  for (var i = 0; i < second_bytes; i++) {
      out[i + first_bytes] <== second[i];
  }
}

template BitsToBytes(bits){
  signal input in[bits];
  signal output out[bits/8];
  for (var i=0; i<bits/8; i++) {
    var bytevalue = 0;
    for (var j=0; j<8; j++) {
      bytevalue |= in[i * 8 + j] ? (1 << (7-j)) : 0;
    }
    out[i] <-- bytevalue;
  }
}
```
