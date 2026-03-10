# Improper Assignment of "NONE" Role Bypasses Admin Permissions


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `43102ce0-cb15-11ef-9d05-1b0897613b78` |
| Commit | `f5f7b8beb513703eb8eec894e1bcb73e71598262` |

## Location

- **Local path:** `./src/contracts/RoleManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/43102ce0-cb15-11ef-9d05-1b0897613b78/source?file=$/github/haven1network/permissions-contracts-sc/f5f7b8beb513703eb8eec894e1bcb73e71598262/contracts/RoleManager.sol
- **Lines:** 70–70

## Description

The issue arises because the role `"NONE"` is being assigned through the function `permissionsInterface.addNewRole("NONE","_orgId",3,true,true)`, which inadvertently bypasses the intended role-based permission checks. When the `"NONE"` role is assigned, it causes the function `permissionsInterface.isOrgAdmin(address(0xDEADBEEF),"_orgId")` to always return true for the given address (e.g., `0xDEADBEEF`). This could allow unauthorized users or addresses to gain admin privileges, effectively bypassing the access control mechanism and potentially compromising the system's security. The issue is caused by the improper handling of the `"NONE"` role, leading to unintended behavior in the role validation logic.

## Recommendation

We recommend implementing input sanitization within the addRole function to explicitly reject the `"NONE"` role during role assignment. By adding a validation check that prevents `"NONE"` from being passed as a role, you can ensure that no unintended or invalid roles are introduced into the system. This prevents the bypass of role-based permission checks and ensures that functions like `permissionsInterface.isOrgAdmin()` operate as intended, maintaining the integrity of the access control mechanism. Proper validation and enforcement of allowed role names are critical to safeguarding the system against unauthorized access and privilege escalation.

## Vulnerable Code

```
require(msg.sender == permUpgradable.getPermImpl(), "invalid caller");
        _;
    }

    /// @notice Sets the Permissions Upgradable address.
    ///
    /// @param _permUpgradable The Permissions Upgradable address.
    constructor(address _permUpgradable) public {
        permUpgradable = PermissionsUpgradable(_permUpgradable);
    }

    /// @notice Adds a new role definition to an organization.
    ///
    /// @param _roleId      The unique identifier for the role being added.
    /// @param _orgId       The org ID to which the role belongs.
    /// @param _baseAccess  Can be from 0 to 7.
    /// @param _isVoter     Whether the role is a voter role.
    /// @param _isAdmin     Whether the role is an admin role.
    ///
    /// @dev Base access can have any of the following values:
    ///
    /// -   0: Read only
    /// -   1: value transfer
    /// -   2: contract deploy
    /// -   3: full access
    /// -   4: contract call
    /// -   5: value transfer and contract call
    /// -   6: value transfer and contract deploy
    /// -   7: contract call and deploy
    function addRole(
        string memory _roleId,
        string memory _orgId,
        uint256 _baseAccess,
        bool _isVoter,
        bool _isAdmin
    ) public onlyImplementation {
        require(_baseAccess < 8, "invalid access value");
        // Check if account already exists
        require(
            roleIndex[keccak256(abi.encode(_roleId, _orgId))] == 0,
            "role exists for the org"
        );
        numberOfRoles++;
        roleIndex[keccak256(abi.encode(_roleId, _orgId))] = numberOfRoles;
        roleList.push(
            RoleDetails(_roleId, _orgId, _baseAccess, _isVoter, _isAdmin, true)
        );
        emit RoleCreated(_roleId, _orgId, _baseAccess, _isVoter, _isAdmin);
    }

    /// @notice Removes an existing role definition from an organization.
    ///
    /// @param _roleId  The unique identifier for the role being removed.
    /// @param _orgId   The org ID to which the role belongs.
    function removeRole(
        string calldata _roleId,
        string calldata _orgId
    ) external onlyImplementation {
        require(
            roleIndex[keccak256(abi.encode(_roleId, _orgId))] != 0,
```
