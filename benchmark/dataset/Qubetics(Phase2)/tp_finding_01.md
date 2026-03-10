# The DKG Protocol Lacks Of Round Check


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `8ecb1290-33f6-11f0-9db2-b3c077248e41` |
| Commit | `cabd16c916df21fbbe7c4a7846e7aed3a5fc0c8f` |

## Location

- **Local path:** `./src/src/adkg_secp256k1/mod.rs`
- **ACC link:** https://acc.audit.certikpowered.info/project/8ecb1290-33f6-11f0-9db2-b3c077248e41/source?file=$/github/Qubetics/qubetics-chain-abstraction/9d3440fe169a63244ca5f3080e36096e090865d6/src/adkg_secp256k1/mod.rs
- **Lines:** 333–339

## Description

Repository:
- `Chain Abstraction`
  
Commit hash:
- [`9d3440fe169a63244ca5f3080e36096e090865d6`](https://github.com/Qubetics/qubetics-chain-abstraction/tree/9d3440fe169a63244ca5f3080e36096e090865d6)
  
Files:
- `src/adkg_secp256k1/mod.rs`

The current implementation of DKG protocol lacks round validation in `DKGMessage::ShareValidation` handling:

**`src/adkg_secp256k1/mod.rs`**
```rust=321
pub async fn handle_message(&mut self, msg: DKGMessage,node_manager: Box<dyn NodeMembership>,
) -> Result<()> {
        match msg {
            DKGMessage::ShareDistribution {
                from,
                shares,
                commitments,
            } => {
                info!("📥 Received share distribution from {}", from);
                self.handle_share_distribution(from, shares, commitments,node_manager.clone())
                    .await?;
            }
            DKGMessage::ShareValidation { from, to, is_valid ,round} => {
                info!(
                    "✅ Received share validation from {} for {}: {}",
                    from, to, is_valid
                );
              >>@audit  self.handle_share_validation(from, to, is_valid,node_manager).await?;
            }
        }
        Ok(())
    }
```
This creates two critical security vulnerabilities:

1. **Cross-round Confusion:** Validation messages from previous rounds can interfere with current round operations
2. **Replay Attacks:** Malicious actors can resend old valid validation messages to disrupt the protocol

## 1 Cross-round Confusion
When a node resets and starts a new DKG round, validation messages from previous rounds could be mistakenly processed as belonging to the current round.

### Attack Flow
1. Normal Operation:
```text
Round 1 DKG completes successfully
Nodes store validation messages from round 1
```

2. Node Reset:
```text
System initiates round 2
round counter increments to 2
Storage may retain old validation data
```

3. Attack Execution:
```text
Old round 1 validation messages remain in network buffers
Nodes receive these stale messages
Messages get processed without round checking
Round 2 DKG gets corrupted by round 1 validations
```

### Impact

1. Invalid threshold signature aggregation
2. Potential key material leakage
3. Consensus failures among nodes


## 2 Replay Attacks
Replayed `true` validations from an earlier round accumulate, driving `check_completion` to satisfy the `valid_validations >= total_nodes * total_nodes` gate and forcing `generate_group_key()` even if the current round has not actually received fresh validations. An attacker who recorded the previous round can replay the entire set of validations (or even a single peer can keep re-broadcasting its old message), resulting in premature DKG completion with potentially stale share data.

### Attack Flow
1. Eavesdropping:
```text
Attacker monitors network during round 1
Records valid ShareValidation messages
```

2. Round Advancement:
```text
System progresses to round 2
Honest nodes generate new polynomials
```

3. Attack Execution:
```text
Attacker replays round 1 validation messages
Messages appear valid but belong to wrong round
Nodes accept them due to missing round check
```

### Impact

1. False validation counts accumulate
2. DKG may complete with invalid shares
3. Final key becomes compromised
4. Enables rogue key generation

## Recommendation

Consider validating round when handling `DKGMessage::ShareValidation`.

## Vulnerable Code

```
shares: Vec<KeyShare>,
        commitments: Vec<SerializablePoint>,
    ) -> Result<()> {
        let dkg_msg = DKGMessage::ShareDistribution {
            from: self.id.clone(),
            shares,
            commitments,
        };

        let gossip_wrap = GossipsubMessage::DKG(dkg_msg);

        let msg_bytes = serde_json::to_vec(&gossip_wrap)?;
        info!("📡 Broadcasting DKG message: {} bytes", msg_bytes.len());
        self.broadcast(MSG_TOPIC_DKG, &msg_bytes).await?;
        Ok(())
    }

    pub async fn handle_message(&mut self, msg: DKGMessage,node_manager: Box<dyn NodeMembership>,
) -> Result<()> {
        match msg {
            DKGMessage::ShareDistribution {
                from,
                shares,
                commitments,
            } => {
                info!("📥 Received share distribution from {}", from);
                self.handle_share_distribution(from, shares, commitments,node_manager.clone())
                    .await?;
            }
            DKGMessage::ShareValidation { from, to, is_valid ,round} => {
                info!(
                    "✅ Received share validation from {} for {}: {}",
                    from, to, is_valid
                );
                self.handle_share_validation(from, to, is_valid,node_manager).await?;
            }
        }
        Ok(())
    }

    async fn handle_share_distribution(
        &mut self,
        from: String,
        shares: Vec<KeyShare>,
        commitments: Vec<SerializablePoint>,
        node_manager: Box<dyn NodeMembership>,
    ) -> Result<()> {
        let raw_commitments: Vec<AffinePoint> = commitments.into_iter().map(|c| c.0).collect();

        let node_index = self.get_node_index(node_manager.clone());

        // Log all shares received from this node
        info!("🔍 [DKG] === SHARE DISTRIBUTION RECEIVED ===");
        info!("📥 [DKG] Node {} received {} shares from node {}", self.id, shares.len(), from);
        
        info!("🔍 [DKG] All shares received from node {}:", from);
        for (i, share) in shares.iter().enumerate() {
            info!(
                "🔍 [DKG] Share {}: index={}, value={:?} (intended for node with index {})",
                i + 1, share.index, share.value.0, share.index
            );
        }
        
        info!("🔍 [DKG] === END SHARE DISTRIBUTION RECEIVED ===");

        info!(
```
