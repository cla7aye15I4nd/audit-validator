from brownie import accounts, config, Land, network
from web3 import Web3 as web3


def deploy_land():
    # Grabbing an account from 0th index of Brownie's ganache default wallets
    account = get_account()
    address1 = "0x4a40E425a8D1EE6279f860d8fd5db3D3661558d6"

    address2 = "0xA9873C4C5FBD0196D0FBA2E50A3EEE216C4D6780"

    addresses = [address1, address2]
    land_deployed = Land.deploy(
        "Silks - Land",
        "SILKSLAND",
        "https://nft.dev.silks.io/metadata/c2Land/",
        262500,
        "0xF0c7B25d85e09058d917ce9B13443920eFf701e7",
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


def get_account():
    if network.show_active == "development":
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])


def main():
    deploy_land()
