from brownie import accounts, config, Marketplace, network, HorsePartnerships
from web3 import Web3 as web3


def deploy_marketplace():
    # Grabbing an account from 0th index of Brownie's ganache default wallets
    account = get_account()
    MP_deployed = Marketplace.deploy(
        "0xF0c7B25d85e09058d917ce9B13443920eFf701e7",
        "0x4a40E425a8D1EE6279f860d8fd5db3D3661558d6",
        {"from": account},
        publish_source=True,
    )

    # print(type(addresses))
    # Brownie knows if this is a transaction or a call automatically

    # Grabbing an account from brownie encrypted accounts section added manually
    # account = accounts.load("mtm")
    # print(account)

    # Grabbing an account from brownie-config.yaml file
    # account = accounts.add(config["wallets"]["from_key"])
    # print(account)
    pass

    # Deploy Horse Fract
    # horse_frac_deployed = HorsePartnerships.deploy(
    #     "nft.dev.silks.io/",
    #     "0xF0c7B25d85e09058d917ce9B13443920eFf701e7",
    #     account,
    #     7,
    #     {"from": account},
    #     publish_source=True,
    # )


def get_account():
    if network.show_active == "development":
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])


def main():
    deploy_marketplace()
