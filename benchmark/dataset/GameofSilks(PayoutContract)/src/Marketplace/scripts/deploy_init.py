from brownie import (
    accounts,
    config,
    Marketplace,
    network,
    Index,
    Land,
    HorsePartnerships,
)
from web3 import Web3 as web3


def deploy_marketplace():
    # Grabbing an account from 0th index of Brownie's ganache default wallets
    account = get_account()

    index_deployed = Index.deploy(
        [],
        [],
        {"from": account},
        publish_source=True,
    )

    # Deploy Land
    land_deployed = Land.deploy(
        "Silks - Land",
        "SILKSLAND",
        "https://nft.dev.silks.io/metadata/c2Land/",
        262500,
        Index[-1],
        {"from": account},
        publish_source=True,
    )
    # Deploy Marketplace
    marketplace_deployed = Marketplace.deploy(
        Index[-1],
        account,
        {"from": account},
        publish_source=True,
    )

    # Deploy Horse Fract
    horse_frac_deployed = HorsePartnerships.deploy(
        "nft.dev.silks.io/",
        Index[-1],
        account,
        7,
        {"from": account},
        publish_source=True,
    )

    # Define Contracts on Index
    Index[-1].setAddress("Marketplace", Marketplace[-1])
    Index[-1].setAddress("Horse", Land[-1])
    Index[-1].setAddress("HorseFractionalization", HorsePartnerships[-1])

    # Set 1155 on Marketplace
    Marketplace[-1].set1155(HorsePartnerships[-1], {"from": account})

    # Unpause HorsePartnerships
    HorsePartnerships[-1].setContractPaused(False, {"from": account})

    # print(type(addresses))
    # Brownie knows if this is a transaction or a call automatically

    # Grabbing an account from brownie encrypted accounts section added manually
    # account = accounts.load("mtm")
    # print(account)

    # Grabbing an account from brownie-config.yaml file
    # account = accounts.add(config["wallets"]["from_key"])
    # print(account)
    pass


def get_account():
    if network.show_active == "development":
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])


def main():
    deploy_marketplace()
