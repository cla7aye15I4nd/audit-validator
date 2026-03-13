from brownie import accounts, config, Farm, network, APIConsumer
from web3 import Web3 as web3


def deploy_land():
    # Grabbing an account from 0th index of Brownie's ganache default wallets
    account = get_account()
    address1 = "0x4a40E425a8D1EE6279f860d8fd5db3D3661558d6"

    address2 = "0xA9873C4C5FBD0196D0FBA2E50A3EEE216C4D6780"

    addresses = [address1, address2]
    farm_deployed = Farm.deploy(
        "Silks - Farm",
        "SILKSFARM",
        "https://portal.dev.silks.io/api/FarmNFTs/FarmNFTs/",
        25600,
        addresses,
        [10, 15],
        address1,
        700,
        "0xF0c7B25d85e09058d917ce9B13443920eFf701e7",
        {"from": account},
        publish_source=True,
    )

    # APIConsumer_deployed = APIConsumer.deploy(
    #     "0xF0c7B25d85e09058d917ce9B13443920eFf701e7",
    #     {"from": account},
    #     publish_source=True,
    # )

    #    /**
    #  * @notice Initialize the link token and target oracle
    #  *
    #  * Goerli Testnet details:
    #  * Link Token: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB
    #  * Oracle: 0xCC79157eb46F5624204f47AB42b3906cAA40eaB7 (Chainlink DevRel)
    #  * jobId: 7d80a6386ef543a3abb52817f6707e3b
    #  *
    #  */

    # APIConsumer_deployed = APIConsumer.deploy(
    #     "0x326C977E6efc84E512bB9C30f76E30c160eD06FB",
    #     "0xCC79157eb46F5624204f47AB42b3906cAA40eaB7",
    #     "7d80a6386ef543a3abb52817f6707e3b",
    #     "0xF0c7B25d85e09058d917ce9B13443920eFf701e7",
    #     {"from": account},
    #     publish_source=True,
    # )

    # farm_deployed.setAPIConsAddress(APIConsumer[-1])
    # farm_deployed.setLandAddress("0x8a2eA5c04D12EAF6E2c1ab06b56E099b43be29E2")
    # farm_deployed.setHorseAddress(Horse[-1])

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
