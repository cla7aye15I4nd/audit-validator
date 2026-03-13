from brownie import (
    accounts,
    config,
    reverts,
    Land,
    Index,
    Marketplace,
    network,
    reverts,
    HorsePartnerships,
)
from web3 import Web3 as web3
import pytest
import time


def deploy_contracts():
    # priority_fee = "2 gwei"
    # max_fee = "10 gwei"
    account = accounts[0]
    # account2 = accounts[1]
    # Deploy Index Contract
    index_deployed = Index.deploy([], [], {"from": account})

    # Deploy Land
    land_deployed = Land.deploy(
        "Silks - Land",
        "SILKSLAND",
        "https://nft.dev.silks.io/metadata/c2Land/",
        262500,
        Index[-1],
        {"from": account},
    )
    # Deploy Marketplace
    marketplace_deployed = Marketplace.deploy(Index[-1], account, {"from": account})

    # Deploy Horse Fract
    horse_frac_deployed = HorsePartnerships.deploy(
        "nft.dev.silks.io/", Index[-1], account, 7, {"from": account}
    )

    # Define Contracts on Index
    Index[-1].setAddress("Marketplace", Marketplace[-1], {"from": account})
    Index[-1].setAddress("Horse", Land[-1], {"from": account})
    Index[-1].setAddress(
        "HorseFractionalization", HorsePartnerships[-1], {"from": account}
    )

    # Set 1155 on Marketplace
    Marketplace[-1].set1155(HorsePartnerships[-1], {"from": account})

    # Unpause HorsePartnerships
    HorsePartnerships[-1].setContractPaused(False, {"from": account})

    # Set index Contract test
    Marketplace[-1].setIndexContractAddress(Index[-1], {"from": account})

    # Set Fee
    Marketplace[-1].setFee("Land", 5, {"from": account})


# ###

# ###


def test_frac_interactions():
    account = accounts[0]
    account2 = accounts[1]
    account3 = accounts[2]
    account4 = accounts[3]
    current_timestamp = int(time.time())
    ts24 = current_timestamp + (24 * 60 * 60)

    deploy_contracts()
    # Mint Horse
    Land[-1].mint(account2, 6, "SkyFalls", True, {"from": account})

    with reverts():
        Marketplace[-1].extDeleteOffer(0, {"from": account})
    with reverts():
        Marketplace[-1].extDeleteMarketItem(0, {"from": account})
    with reverts():
        Marketplace[-1].extDeleteMarketItems("Horse", account, 0, 1, {"from": account})

    with reverts():
        Marketplace[-1].setIndexContractAddress(
            "0x0000000000000000000000000000000000000000", {"from": account}
        )
    with reverts():
        Marketplace[-1].set1155(
            "0x0000000000000000000000000000000000000000", {"from": account}
        )

    # Set approval for HorseFractionalization & Horse Contract
    Land[-1].setApprovalForAll(Marketplace[-1], True, {"from": account2})
    HorsePartnerships[-1].setApprovalForAll(Marketplace[-1], True, {"from": account2})

    # Fractionalize Horse and check balance without listings or offers
    HorsePartnerships[-1].fractionalize(1, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 1, {"from": account2}) == 9

    # List Horse
    Marketplace[-1].createMarketItem(Land[-1], 0, 7, 1, ts24, {"from": account2})
    assert Marketplace[-1].fetchMarketItemsbyID(1) != ""

    # Make Offers on Horse
    Marketplace[-1].makeOffer(Land[-1], 0, 1, {"from": account3, "value": 1000000000})
    assert Marketplace[-1].getAllOffers(Land[-1], 0) != ""

    # Fractionalize Horse and check balance
    HorsePartnerships[-1].fractionalize(0, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 0, {"from": account2}) == 9

    # Verify listings and offers are gone
    # with reverts():
    #     assert Marketplace[-1].fetchMarketSizebyAddress(Land[-1]) == 0
    #     assert Marketplace[-1].getAllOffers(Land[-1], 0) == ""

    # List Fractionalized pieces with amount > on listings
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 0, 7, 1, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 0, 7, 2, ts24, {"from": account2}
    )

    HorsePartnerships[-1].safeTransferFrom(
        account2, account, 0, 5, "", {"from": account2}
    )

    # List Fractionalized pieces < amount on listings
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 0, 7, 3, ts24, {"from": account2}
    )
    HorsePartnerships[-1].safeTransferFrom(
        account2, account, 0, 2, "", {"from": account2}
    )

    # Fractionalize Horse and check balance without listings or offers
    HorsePartnerships[-1].fractionalize(2, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 2, {"from": account2}) == 9

    # List Fractionalized pieces just 1 listing
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 2, 7, 3, ts24, {"from": account2}
    )

    HorsePartnerships[-1].safeTransferFrom(
        account2, account, 2, 7, "", {"from": account2}
    )


###


def test_offers_Land():
    # account = get_account(0)
    # account2 = get_account(1)
    # account3 = get_account(2)
    account = accounts[0]
    account2 = accounts[1]
    account3 = accounts[2]
    account4 = accounts[3]
    deploy_contracts()

    Land[-1].mint(account2, 6, "SkyFalls", True, {"from": account})
    Land[-1].mint(account, 6, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account2, {"from": account2}) == 6
    assert Land[-1].balanceOf(account, {"from": account}) == 6

    # Make Offer for 0 FAIL
    with reverts():
        Marketplace[-1].makeOffer(
            HorsePartnerships[-1], 0, 0, {"from": account3, "value": 1000000000}
        )
    # Set Floor price
    Marketplace[-1].changeFloorPrice("Horse", 4, {"from": account})

    # Make Offer below floor price FAIL
    with reverts():
        Marketplace[-1].makeOffer(Land[-1], 1, 1, {"from": account3, "value": 3})
    # Make offer for non silks asset
    with reverts():
        Marketplace[-1].makeOffer(account2, 0, 5, {"from": account3, "value": 3})
    # Make Offer For more than 1 FAIL
    with reverts():
        Marketplace[-1].makeOffer(
            Land[-1], 1, 5, {"from": account3, "value": 1000000000}
        )

    # Make Offer success
    Marketplace[-1].makeOffer(Land[-1], 1, 1, {"from": account3, "value": 1000000000})

    # assert account3.balance() == 99999999999000000000

    # Accept Offer without setapprovalforAll
    with reverts():
        Marketplace[-1].acceptOffer(Land[-1], 1, 0, 1, {"from": account2})

    # Set approval for HorseFractionalization Contract
    Land[-1].setApprovalForAll(Marketplace[-1], True, {"from": account2})

    # Accept Your own offer. FAIL
    with reverts():
        Marketplace[-1].acceptOffer(Land[-1], 1, 0, 1, {"from": account3})

    # Accept Offer for 0. FAIL
    with reverts():
        Marketplace[-1].acceptOffer(Land[-1], 1, 0, 0, {"from": account2})

    # Accept offer for asset you don't own
    with reverts():
        Marketplace[-1].acceptOffer(Land[-1], 1, 0, 1, {"from": account4})

    # Accept Partial Offer and check balance
    Marketplace[-1].acceptOffer(Land[-1], 1, 0, 1, {"from": account2})

    # assert account2.balance() == 100000000001000000000

    #######

    # Make 2 Offers and try to cancel from 3rd wallet
    Marketplace[-1].makeOffer(Land[-1], 2, 1, {"from": account3, "value": 1000000000})
    Marketplace[-1].makeOffer(Land[-1], 2, 1, {"from": account3, "value": 1000000000})
    with reverts():
        Marketplace[-1].deleteOffer(Land[-1], 2, 0, {"from": account})

    # Cancel Offer successfully from offerer
    Marketplace[-1].deleteOffer(Land[-1], 2, 0, {"from": account3})

    #  Cancel 2nd offer successfully from owner because its a 721
    Marketplace[-1].deleteOffer(Land[-1], 2, 1, {"from": account2})

    # Cancel Offer again FAIL because doesn't exist
    with reverts():
        Marketplace[-1].deleteOffer(Land[-1], 2, 0, {"from": account3})

    # Make 2 Offers and verify that the accepted one gets deleted so we can accept the 0th one twice
    Marketplace[-1].makeOffer(Land[-1], 3, 1, {"from": account3, "value": 1000000000})
    Marketplace[-1].makeOffer(Land[-1], 3, 1, {"from": account3, "value": 1000000000})
    Marketplace[-1].getOffer(Land[-1], 3, 1, {"from": account})
    Marketplace[-1].acceptOffer(Land[-1], 3, 0, 1, {"from": account2})
    # Second accept should fail since now this guy doesnt own it
    with reverts():
        Marketplace[-1].acceptOffer(Land[-1], 3, 0, 1, {"from": account2})

    #######
    # Make Offer on Token you already own should pass for Partnership and fail for others
    with reverts():
        Marketplace[-1].makeOffer(
            Land[-1], 4, 1, {"from": account2, "value": 1000000000}
        )

    # TEST RO FUNCTIONS
    Marketplace[-1].getAllOffers(Land[-1], 0, {"from": account})


#


def test_offers_HorsePartnerships():
    # account = get_account(0)
    # account2 = get_account(1)
    # account3 = get_account(2)
    account = accounts[0]
    account2 = accounts[1]
    account3 = accounts[2]
    account4 = accounts[3]
    deploy_contracts()

    Land[-1].mint(account2, 6, "SkyFalls", True, {"from": account})
    Land[-1].mint(account, 6, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account2, {"from": account2}) == 6
    assert Land[-1].balanceOf(account, {"from": account}) == 6

    # Fractionalize Horse and check balance
    HorsePartnerships[-1].fractionalize(0, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 0, {"from": account2}) == 9

    # Make Offer for 0 FAIL
    with reverts():
        Marketplace[-1].makeOffer(
            HorsePartnerships[-1], 0, 0, {"from": account3, "value": 1000000000}
        )
    # Set Floor price
    Marketplace[-1].changeFloorPrice("HorseFractionalization", 4, {"from": account})

    # Make Offer below floor price FAIL
    with reverts():
        Marketplace[-1].makeOffer(
            HorsePartnerships[-1], 0, 5, {"from": account3, "value": 3}
        )
    # Make offer for non silks asset
    with reverts():
        Marketplace[-1].makeOffer(account2, 0, 5, {"from": account3, "value": 3})

    # Make Offer success
    Marketplace[-1].makeOffer(
        HorsePartnerships[-1], 0, 5, {"from": account3, "value": 1000000000}
    )

    # assert account3.balance() == 99999999999000000000

    # Accept Partial Offer without setapprovalforAll
    with reverts():
        Marketplace[-1].acceptOffer(HorsePartnerships[-1], 0, 0, 1, {"from": account2})

    # Set approval for HorseFractionalization Contract
    HorsePartnerships[-1].setApprovalForAll(Marketplace[-1], True, {"from": account2})

    # Accept Your own offer. FAIL
    with reverts():
        Marketplace[-1].acceptOffer(HorsePartnerships[-1], 0, 0, 1, {"from": account3})

    # Accept Offer for 0. FAIL
    with reverts():
        Marketplace[-1].acceptOffer(HorsePartnerships[-1], 0, 0, 0, {"from": account2})

    # Accept offer for asset you don't own
    with reverts():
        Marketplace[-1].acceptOffer(HorsePartnerships[-1], 0, 0, 1, {"from": account4})

    # Accept Partial Offer and check balance
    Marketplace[-1].acceptOffer(HorsePartnerships[-1], 0, 0, 1, {"from": account2})

    # assert account2.balance() == 100000000000200000000

    # Accept remaining Offer
    Marketplace[-1].acceptOffer(HorsePartnerships[-1], 0, 0, 4, {"from": account2})

    # assert account2.balance() == 100000000001000000000

    #######

    # Fractionalize Horse and check balance
    HorsePartnerships[-1].fractionalize(1, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 1, {"from": account2}) == 9

    # Make Offer and try to cancel from 3rd wallet
    Marketplace[-1].makeOffer(
        HorsePartnerships[-1], 1, 5, {"from": account3, "value": 1000000000}
    )
    with reverts():
        Marketplace[-1].deleteOffer(HorsePartnerships[-1], 1, 0, {"from": account})

    # Cancel Offer successfully from offerer
    Marketplace[-1].deleteOffer(HorsePartnerships[-1], 1, 0, {"from": account3})

    # Cancel Offer again FAIL because doesn't exist
    with reverts():
        Marketplace[-1].deleteOffer(HorsePartnerships[-1], 1, 0, {"from": account3})

    # Fail to Cancel offer successfully from owner because its an 1155
    with reverts():
        Marketplace[-1].deleteOffer(HorsePartnerships[-1], 1, 0, {"from": account2})

    # Fractionalize Horse and check balance
    HorsePartnerships[-1].fractionalize(2, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 2, {"from": account2}) == 9

    # Make 2 Offers and verify that the accepted one gets deleted so we can accept the 0th one twice
    Marketplace[-1].makeOffer(
        HorsePartnerships[-1], 2, 3, {"from": account3, "value": 1000000000}
    )
    Marketplace[-1].makeOffer(
        HorsePartnerships[-1], 2, 1, {"from": account3, "value": 1000000000}
    )
    Marketplace[-1].getOffer(HorsePartnerships[-1], 2, 1, {"from": account})
    Marketplace[-1].acceptOffer(HorsePartnerships[-1], 2, 0, 3, {"from": account2})
    Marketplace[-1].acceptOffer(HorsePartnerships[-1], 2, 1, 1, {"from": account2})

    #######
    # Fractionalize Horse and check balance
    HorsePartnerships[-1].fractionalize(3, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 3, {"from": account2}) == 9

    # Make Offer on Token you already own should pass for Partnership and fail for others
    Marketplace[-1].makeOffer(
        HorsePartnerships[-1], 3, 5, {"from": account2, "value": 1000000000}
    )

    # TEST RO FUNCTIONS
    Marketplace[-1].getAllOffers(HorsePartnerships[-1], 0, {"from": account})


#


#


#


#
def test_marketplace_item_HorsePartnerships():
    # account = get_account(0)
    # account2 = get_account(1)
    # account3 = get_account(2)
    account = accounts[0]
    account2 = accounts[1]
    account3 = accounts[2]
    deploy_contracts()
    current_timestamp = int(time.time())
    ts24 = current_timestamp + (24 * 60 * 60)
    tsExp = current_timestamp - (24 * 60 * 60)

    # Testing RO functions at beginning without reverts

    print(Marketplace[-1].fetchAllMarketItems())
    print(Marketplace[-1].fetchMarketItemsbyAddress(HorsePartnerships[-1]))
    print(Marketplace[-1].fetchMarketSizebyAddress(HorsePartnerships[-1]))
    print(Marketplace[-1].fetchUnsoldMarketItems())

    # Test Basic Mint
    Land[-1].mint(account2, 7, "SkyFalls", True, {"from": account})
    Land[-1].mint(account, 7, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account2, {"from": account2}) == 7
    assert Land[-1].balanceOf(account, {"from": account}) == 7

    # Setting floor price
    Marketplace[-1].changeFloorPrice("HorseFractionalization", 4, {"from": account})

    # Fractionalize Horse and check balance
    HorsePartnerships[-1].fractionalize(0, {"from": account2})
    assert HorsePartnerships[-1].balanceOf(account2, 0, {"from": account2}) == 9

    # Test Listing asset without setApprovalForAll
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 0, 7, 1, ts24, {"from": account2}
        )
    # Test Listing asset with quantity 0
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 0, 7, 0, ts24, {"from": account2}
        )
    # Test Listing non-silks asset
    with reverts():
        Marketplace[-1].createMarketItem(account2, 0, 7, 1, ts24, {"from": account2})

    # Set approval for HorseFractionalization Contract
    HorsePartnerships[-1].setApprovalForAll(Marketplace[-1], True, {"from": account2})

    # Test listing below floor price
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 0, 3, 9, ts24, {"from": account2}
        )

    # Test Listing all 9 of Partnership asset and checking asset still in wallet
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 0, 7, 9, ts24, {"from": account2}
    )
    assert HorsePartnerships[-1].balanceOf(account2, 0, {"from": account2}) == 9

    # Checking that Marketplace item came up successfully
    print(Marketplace[-1].fetchMarketItemsbyID(1))
    assert Marketplace[-1].fetchMarketItemsbyID(1)[3] == account2

    # Test Listing same asset again fails
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 0, 7, 1, ts24, {"from": account2}
        )
    # Test Listing same asset again only like 1 fails
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 0, 1, 1, ts24, {"from": account2}
        )

    # Test listing asset you don't own
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 1, 7, 1, ts24, {"from": account}
        )

    # Test listing asset doesn't exist
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 10, 7, 1, ts24, {"from": account2}
        )

    # Test purchasing asset with Less money than listed
    with reverts():
        Marketplace[-1].createMarketSale(1, 1, {"from": account, "value": 5})

    # Test purchasing asset from same account that listed it
    with reverts():
        Marketplace[-1].createMarketSale(1, 1, {"from": account2, "value": 7})

    # Test failed purchase of 0 items
    with reverts():
        Marketplace[-1].createMarketSale(1, 0, {"from": account, "value": 7})

    # Test successful purchase of 1 item
    print(Marketplace[-1].marketItems(1))
    Marketplace[-1].createMarketSale(1, 1, {"from": account, "value": 7})

    assert HorsePartnerships[-1].balanceOf(account, 0, {"from": account}) == 1
    assert HorsePartnerships[-1].balanceOf(account2, 0, {"from": account2}) == 8

    # Test purchasing remaing 8 assets with Less money than listed
    with reverts():
        Marketplace[-1].createMarketSale(8, 6, {"from": account, "value": 55})

    # Test successful purchase of Remaining 6 items
    Marketplace[-1].createMarketSale(1, 8, {"from": account, "value": 56})

    assert HorsePartnerships[-1].balanceOf(account, 0, {"from": account}) == 9
    assert HorsePartnerships[-1].balanceOf(account2, 0, {"from": account2}) == 0

    # Test listing asset you just bought after SetApprovalForAll
    HorsePartnerships[-1].setApprovalForAll(Marketplace[-1], True, {"from": account})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 0, 7, 1, ts24, {"from": account}
    )

    # Test fails second time from different user since all items already bought
    with reverts():
        Marketplace[-1].createMarketSale(1, 1, {"from": account3, "value": 14})

    # Test buying successful with more money with fresh frac
    HorsePartnerships[-1].fractionalize(1, {"from": account2})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 1, 8, 1, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketSale(3, 1, {"from": account, "value": 10})

    # Test cancelling listing with wrong account
    HorsePartnerships[-1].fractionalize(2, {"from": account2})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 2, 8, 1, ts24, {"from": account2}
    )

    with reverts():
        Marketplace[-1].deleteMarketItem(4, {"from": account})
    # Test cancel fails also with item doesnt exist
    with reverts():
        Marketplace[-1].deleteMarketItem(5, {"from": account})

    # Test Cancelling Listing Successfully
    Marketplace[-1].deleteMarketItem(4, {"from": account2})

    # Random Check Unsold items
    print(Marketplace[-1].fetchUnsoldMarketItems())

    # Test can't buy now that its cancelled
    with reverts():
        Marketplace[-1].createMarketSale(4, 1, {"from": account, "value": 10})

    # Test listing same asset multiple times fails.
    HorsePartnerships[-1].fractionalize(3, {"from": account2})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 3, 4, 8, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketSale(5, 8, {"from": account, "value": 32})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 3, 5, 1, ts24, {"from": account2}
    )
    with reverts():
        Marketplace[-1].createMarketItem(
            HorsePartnerships[-1], 3, 5, 1, ts24, {"from": account2}
        )

    # Test multiple listings and older one sells to delete item from array
    HorsePartnerships[-1].fractionalize(4, {"from": account2})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 4, 4, 2, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 4, 4, 4, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketSale(7, 2, {"from": account, "value": 32})

    # Test multiple listings and newer one sells to delete item from array
    HorsePartnerships[-1].fractionalize(5, {"from": account2})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 5, 4, 2, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 5, 4, 4, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketSale(10, 4, {"from": account, "value": 32})

    # List expired item
    HorsePartnerships[-1].fractionalize(6, {"from": account2})
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 6, 4, 2, tsExp, {"from": account2}
    )
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 6, 4, 1, ts24, {"from": account2}
    )
    Marketplace[-1].createMarketItem(
        HorsePartnerships[-1], 6, 4, 1, ts24, {"from": account2}
    )

    # Testing RO functions
    print(Marketplace[-1].fetchAllMarketItems())
    print(Marketplace[-1].fetchMarketItemsbyAddress(HorsePartnerships[-1]))
    print(Marketplace[-1].fetchMarketSizebyAddress(HorsePartnerships[-1]))
    print(Marketplace[-1].fetchUnsoldMarketItems())
    Marketplace[-1].fetchMarketItemsbyID(7)


def test_marketplace_item_land():
    account = accounts[0]
    account2 = accounts[1]
    account3 = accounts[2]
    deploy_contracts()
    current_timestamp = int(time.time())
    ts24 = current_timestamp + (24 * 60 * 60)

    # Test Basic Mint
    Land[-1].mint(account2, 5, "SkyFalls", True, {"from": account})
    assert Land[-1].balanceOf(account2, {"from": account2}) == 5
    assert Land[-1].balanceOf(account, {"from": account}) == 0

    # Test Listing asset without setApprovalForAll
    with reverts():
        Marketplace[-1].createMarketItem(Land[-1], 0, 7, 1, ts24, {"from": account2})

    Land[-1].setApprovalForAll(Marketplace[-1], True, {"from": account2})

    # Test listing more than 1 assset for 721
    with reverts():
        Marketplace[-1].createMarketItem(Land[-1], 0, 7, 10, ts24, {"from": account2})

    # Test Listing asset and checking asset still in wallet
    Marketplace[-1].createMarketItem(Land[-1], 0, 7, 1, ts24, {"from": account2})
    assert Land[-1].balanceOf(account2, {"from": account}) == 5

    # Checking that Marketplace item came up successfully
    print(Marketplace[-1].fetchMarketItemsbyID(1))
    assert Marketplace[-1].fetchMarketItemsbyID(1)[3] == account2

    # Test Listing same asset again fails
    with reverts():
        Marketplace[-1].createMarketItem(Land[-1], 0, 7, 1, ts24, {"from": account2})

    # Test listing asset you don't own
    with reverts():
        Marketplace[-1].createMarketItem(Land[-1], 1, 7, 1, ts24, {"from": account})

    # Test listing asset doesn't exist
    with reverts():
        Marketplace[-1].createMarketItem(Land[-1], 10, 7, 1, ts24, {"from": account2})

    # Test purchasing asset with Less money than listed
    with reverts():
        Marketplace[-1].createMarketSale(1, 1, {"from": account, "value": 5})
    # Test purchasing asset from same account that listed it
    with reverts():
        Marketplace[-1].createMarketSale(1, 1, {"from": account2, "value": 7})

    # Test failed purchase of 0 items
    with reverts():
        Marketplace[-1].createMarketSale(1, 0, {"from": account, "value": 7})

    # Test failed purchase of 2 items
    with reverts():
        Marketplace[-1].createMarketSale(1, 2, {"from": account, "value": 7})

    # Test successful purchase
    Marketplace[-1].createMarketSale(1, 1, {"from": account, "value": 7})

    assert Land[-1].ownerOf(0, {"from": account}) == account

    # Fail to Delete listing
    with reverts():
        Marketplace[-1].deleteMarketItem(1, {"from": account2})

    # Test fails second time from different user since item already bought
    with reverts():
        Marketplace[-1].createMarketSale(1, 1, {"from": account3, "value": 7})

    # Test buying successful with more money
    Marketplace[-1].createMarketItem(Land[-1], 1, 8, 1, ts24, {"from": account2})
    Marketplace[-1].createMarketSale(2, 1, {"from": account, "value": 10})

    # Test cancelling listing with wrong account
    Marketplace[-1].createMarketItem(Land[-1], 2, 8, 1, ts24, {"from": account2})
    with reverts():
        Marketplace[-1].deleteMarketItem(3, {"from": account})
    # Test cancel fails also with item doesnt exist
    with reverts():
        Marketplace[-1].deleteMarketItem(4, {"from": account})

    # Test Cancelling Listing Successfully
    Marketplace[-1].deleteMarketItem(3, {"from": account2})

    # Test relisting the same asset
    Marketplace[-1].createMarketItem(Land[-1], 2, 8, 1, ts24, {"from": account2})


def get_account(num):
    if network.show_active == "development":
        return accounts[num]
    else:
        return accounts.add(config["wallets"]["from_key" + str(num)])
