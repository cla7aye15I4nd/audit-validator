
## Contract Functionality

### `payout(Payment[] memory payments)`

Allows the contract owner to distribute Ether to multiple addresses. The function takes an array of `Payment` structs, each containing a payee's address and the amount to be paid.

## Test Cases

- **Deployment**: Tests if the contract is deployed correctly and the role is set.
- **Payout**: Tests various scenarios including successful payments, role has access, handling insufficient funds, and refunding excess Ether.
