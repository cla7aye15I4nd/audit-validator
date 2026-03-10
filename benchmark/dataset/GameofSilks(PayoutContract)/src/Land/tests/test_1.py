from brownie import accounts, config, reverts, Land, Index, SkyFalls, network, reverts
from web3 import Web3 as web3
import pytest


def deploy_land():
    # priority_fee = "2 gwei"
    # max_fee = "10 gwei"
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    # Deploy Index Contract
    index_deployed = Index.deploy([], [], {"from": account})
    # Deploy SkyFalls Contract
    skyfalls_deployed = SkyFalls.deploy({"from": account})

    # Deploy Land
    land_deployed = Land.deploy(
        "Silks - Land",
        "SILKSLAND",
        "https://nft.dev.silks.io/metadata/c2Land/",
        262500,
        Index[-1],
        {"from": account},
    )
    # Define Contracts on Index
    Index[-1].setAddress("SkyFalls", SkyFalls[-1])
    Index[-1].setAddress("Land", Land[-1])

    SkyFalls[-1].setSilksMigrateToContract(Land[-1])
    SkyFalls[-1].toggleMigration()


def test_land_mint():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()
    # Mint SkyFalls tokens
    SkyFalls[-1].airdropGiveaway([account], [100])
    assert SkyFalls[-1].balanceOf(account, 1) == 100

    # Test Basic Mint
    Land[-1].mint(account2, 5, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account2, {"from": account}) == 5

    # Fail
    with reverts():
        Land[-1].mint(account2, 5, "SkyFalls", True, {"from": account2})

    # Testing SkyFalls migrate
    SkyFalls[-1].migrateTokens([1], [1], {"from": account})

    # Testing fail
    with reverts():
        Land[-1].mintTransfer(account, 5, {"from": account})
    with reverts():
        Land[-1].mint(
            "0x0000000000000000000000000000000000000000",
            1,
            "SkyFalls",
            True,
            {"from": account},
        )
    with reverts():
        Land[-1].mint(account2, 262501, "SkyFalls", True, {"from": account})

    with reverts():
        Land[-1].mint(account2, 9999999999999999, "SkyFalls", True, {"from": account})

    Land[-1].tokenURI(
        1,
        {"from": account2},
    )
    with reverts():
        Land[-1].tokenURI(
            999999,
            {"from": account2},
        )
    with reverts():
        Land[-1].safeTransferFrom(
            account2,
            "0x0000000000000000000000000000000000000000",
            4,
            {"from": account2},
        )
    with reverts():
        Land[-1].burn(4, {"from": account2})
    with reverts():
        Land[-1].burn(6, {"from": account2})


def test_land_mint_rv():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()
    # Test Mint Fail. Assert balance still same
    with reverts():
        Land[-1].mint(account2, 0, "SkyFalls", True, {"from": account2})


def test_land_mint_rv_2():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()
    # Test Mint Fail. Assert balance still same
    with reverts():
        Land[-1].mint(
            "0x0000000000000000000000000000000000000000",
            1,
            "SkyFalls",
            True,
            {"from": account2},
        )


def test_land_view():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()

    with reverts():
        Land[-1].getApproved(
            1,
            {"from": account2},
        )
    with reverts():
        Land[-1].tokenURI(
            1,
            {"from": account2},
        )
    with reverts():
        Land[-1].balanceOf(
            "0x0000000000000000000000000000000000000000", {"from": account}
        )
    with reverts():
        Land[-1].getApproved(
            25,
            {"from": account2},
        )


def test_approve():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()
    # approval then transfer
    Land[-1].mint(account, 5, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account, {"from": account}) == 5
    # Test transfer
    Land[-1].transferFrom(account, account2, 0, {"from": account})
    with reverts():
        Land[-1].transferFrom(
            account, "0x0000000000000000000000000000000000000000", 0, {"from": account}
        )

    with reverts():
        # Test reversal
        Land[-1].transferFrom(account, account2, 0, {"from": account2})
    Land[-1].approve(account2, 1, {"from": account})
    with reverts():
        Land[-1].approve(account2, 25, {"from": account})
    Land[-1].transferFrom(account, account2, 1, {"from": account2})
    with reverts():
        Land[-1].safeTransferFrom(account, account2, 1, {"from": account2})
    Land[-1].setApprovalForAll(account2, True, {"from": account})
    Land[-1].safeTransferFrom(account2, account, 1, {"from": account2})
    Land[-1].getApproved(
        1,
        {"from": account2},
    )


def test_ext_mint():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()
    # Setting extMintAddress then testing extMint
    with reverts():
        Land[-1].extMintFree(account2, 5, "SkyFalls", True, {"from": account})
    with reverts():
        Land[-1].setExtMintAddress(account2, {"from": account2})
    with reverts():
        Land[-1].setExtMintAddress(
            "0x0000000000000000000000000000000000000000", {"from": account}
        )
    Land[-1].setExtMintAddress(account, {"from": account})
    Land[-1].extMintFree(account2, 5, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account2, {"from": account}) == 5
    Land[-1].extMintFree(account, 5, "SkyFalls", True, {"from": account})
    with reverts():
        Land[-1].extBurn(5, {"from": account})
    Land[-1].whiteListChange(account, True, {"from": account})
    Land[-1].extBurn(5, {"from": account})
    with reverts():
        Land[-1].extBurn(6, {"from": account2})


def test_transferownership():
    account = get_account()
    account2 = "0x39a442d91A12FA78aCa7276e98f4fAD894ba947B"
    deploy_land()
    Land[-1].transferOwnership(
        account2,
        {"from": account},
    )
    with reverts():
        Land[-1].transferOwnership(
            account2,
            {"from": account},
        )
    with reverts():
        Land[-1].transferOwnership(
            "0x0000000000000000000000000000000000000000",
            {"from": account2},
        )
    Land[-1].owner(
        {"from": account2},
    )


def get_account():
    i = -1
    if network.show_active == "development":
        i += 1
        return accounts[i]
    else:
        return accounts.add(config["wallets"]["from_key"])
