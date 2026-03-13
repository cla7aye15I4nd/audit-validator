from time import sleep
from brownie import accounts, config, Horse, VRFV2, Index, network
from web3 import Web3 as web3


def test_mint():
    account = get_account()
    address1 = "0x4a40E425a8D1EE6279f860d8fd5db3D3661558d6"
    address2 = "0xA9873C4C5FBD0196D0FBA2E50A3EEE216C4D6780"
    addresses = [address1, address2]
    Horse[-1].adminMintTransferReq(7, {"from": account})
    sleep(300)
    # Giving time for the VRF to process the random function. Note, the VRF Consumer address must be added to the subscription given in the contract
    Horse[-1].adminMintTransferFul(account, {"from": account})
    assert Horse[-1].balanceOf(account, {"from": account}) == 7


def get_account():
    if network.show_active == "development":
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])


def main():
    test_mint()
