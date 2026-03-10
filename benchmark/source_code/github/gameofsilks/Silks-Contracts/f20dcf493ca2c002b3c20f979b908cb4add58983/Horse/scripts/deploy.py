from brownie import accounts, config, Horse, VRFV2, Index, network
from web3 import Web3 as web3


def deploy_horse():
    # Grabbing an account from 0th index of Brownie's ganache default wallets
    account = get_account()
    # Index.deploy([], [], {"from": account}, publish_source=True)
    # horse_deployed = Horse.deploy(
    #     "Silks - Horse",
    #     "SILKSHORSE",
    #     "https://nft.silks.io/metadata/c1/",
    #     10000000,
    #     ["0x7edAC4f0251a484a28F757d8f6e83783a1f38285"],
    #     [100],
    #     "0x7edAC4f0251a484a28F757d8f6e83783a1f38285",
    #     800,
    #     Index[-1],
    #     {"from": account},
    #     publish_source=True,
    # )
    vrfv2_deployed = VRFV2.deploy(
        484,
        "0x271682DEB8C4E0901D1a1550aD2e64D568E69909",
        "0xff8dedfbfa60af186cf3c830acbc32c05aae823045ae5ea7da1e45fbfaba4f92",
        Index[-1],
        {"from": account},
        publish_source=True,
    )
    # Index[-1].setAddress("Horse", Horse[-1], {"from": account})
    Index[-1].setAddress("VRFV2", VRFV2[-1], {"from": account})
    pass


def get_account():
    # if network.show_active == "development":
    #     return accounts[0]
    # elif network.show_active == "goerli":
    #     return accounts.add(config["wallets"]["from_key"])
    # elif network.show_active == "mainnet":
    return accounts.add(config["wallets"]["prod_key"])


def main():
    deploy_horse()
