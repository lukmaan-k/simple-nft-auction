// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./utils/Utils.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";
import "../src/mocks/MockERC1155.sol";
import "../src/Auction.sol";


contract AuctionTest is Test, IAuction {
    Utils utils;
    address payable[] users;

    address seller; // Also the deployer/owner of the Auction contract
    address alice; // Buyer 1
    address bob; // Buyer 2

    MockERC20 mockErc20;
    MockERC721 mockErc721;
    MockERC1155 mockErc1155;
    Auction auction;

    uint256 reservePrice = 10 ether;
    uint256 auctionDuration = 6 hours;
    uint256 startingCurrencyAmount = 10000;
    uint256 minBidIncrementBps = 100; // 1%
    uint32 softClosePeriod = 3 minutes;
    uint32 auctionExtensionPeriod = 2 minutes;
    uint256 auctionId = 0;

    function setUp() public {

        utils = new Utils();
        users = utils.createUsers(3, startingCurrencyAmount); // Make 3 users
        seller = users[0];
        vm.label(seller, "Seller");
        alice = users[1];
        vm.label(alice, "Alice");
        bob = users[2];
        vm.label(bob, "Bob");

        _deploy();
        _mintInitialTokens();
    }

    // Confirm deployment
    function test001() external view {
        assert(keccak256(bytes(mockErc20.name())) == keccak256(bytes("MockERC20")));
        assert(keccak256(bytes(mockErc721.name())) == keccak256(bytes("MockERC721")));
        assert(keccak256(bytes(mockErc1155.uri(0))) == keccak256(bytes("someUri")));
        assert(auction.owner() == seller);
    }

    // Confirm that an auction can be created for ERC721 nfts with ETH as the wanted currency
    function test002() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.ACTIVE);
        assert(mockErc721.ownerOf(0) == address(auction));
    }

    // Confirm that an auction can be created for ERC721 nfts with an ERC20 as the wanted currency
    function test003() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(mockErc20));
        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.ACTIVE);
        assert(mockErc721.ownerOf(0) == address(auction));
    }

    // Same as test002 but for ERC1155
    function test004() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc1155), 0, 5, IAuction.TOKEN_TYPE.ERC1155, address(0));
        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.ACTIVE);
        assert(mockErc1155.balanceOf(address(auction), 0) == 5);
    }

    // Same as test003 but for ERC1155
    function test005() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc1155), 0, 5, IAuction.TOKEN_TYPE.ERC1155, address(mockErc20));
        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.ACTIVE);
        assert(mockErc1155.balanceOf(address(auction), 0) == 5);
    }

    // Confirm that an auction cannot be bid on if price is below reserve price
    function test006() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 bidAmount = reservePrice / 2;
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidBidAmount.selector, bidAmount));
        auction.bid{value: bidAmount}(auctionId, bidAmount);
    }

    // Confirm that an auction can be bid on with ETH (if at or above reserve price)
    function test007() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 bidAmount = reservePrice;
        vm.expectEmit(address(auction));
        emit IAuction.NewBid(auctionId, alice, bidAmount);
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.winningBid.bidder == payable(alice));
        assert(listing.winningBid.amount == bidAmount);
        assert(listing.status == IAuction.STATUS.ACTIVE);
        assert(address(auction).balance == bidAmount);
    }

    // Confirm that an auction can be bid on with ERC20 (if at or above reserve price)
    function test008() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(mockErc20));
        vm.stopPrank();
        
        vm.startPrank(alice);
        uint256 bidAmount = reservePrice;
        vm.expectEmit(address(auction));
        emit IAuction.NewBid(auctionId, alice, bidAmount);
        auction.bid(auctionId, bidAmount);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.winningBid.bidder == payable(alice));
        assert(listing.winningBid.amount == bidAmount);
        assert(listing.status == IAuction.STATUS.ACTIVE);
        assert(mockErc20.balanceOf(address(auction)) == bidAmount);
    }

    // Confirm that a new bid cannot be placed if it is not higher than the previous bid plus the minimum bid increment
    function test009() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        uint256 bidAmount = reservePrice;
        vm.prank(alice);
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        vm.startPrank(bob);
        bidAmount = bidAmount + 0.01 ether; // Needs to be at least 10.1 ETH (+ 1%) to be valid
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidBidAmount.selector, bidAmount)); // Bob's bid reverts
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.winningBid.bidder == alice); // Still alice
    }

    // Confirm that a new bid can be placed if it is higher than the previous bid plus the minimum bid increment
    function test010() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        uint256 bidAmount = reservePrice;
        vm.prank(alice);
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        vm.startPrank(bob);
        bidAmount = bidAmount + 0.1 ether; // Needs to be at least 10.1 ETH (+ 1%) to be valid
        vm.expectEmit(address(auction));
        emit IAuction.NewBid(auctionId, bob, bidAmount);
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.winningBid.bidder == payable(bob));
        assert(listing.winningBid.amount == bidAmount);
        assert(address(auction).balance == bidAmount);
        assert(alice.balance == startingCurrencyAmount * 1 ether);
        assert(bob.balance == startingCurrencyAmount * 1 ether - bidAmount);
    }

    // Confirm that an auction is extended if a bid is placed in the final softclose period
    function test011() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();
        
        IAuction.AuctionParams memory listing = auction.getAuction(0);
        uint32 oldEndtime = listing.endTime;

        uint256 bidAmount = reservePrice;
        vm.prank(alice);
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        // Wait 1 hour and 59 minutes
        vm.warp(block.timestamp + 5 hours + 58 minutes);
        vm.startPrank(bob);
        bidAmount = bidAmount + 0.1 ether;
        auction.bid{value: bidAmount}(auctionId, bidAmount);

        listing = auction.getAuction(0);
        assert(listing.endTime == uint32(oldEndtime + auctionExtensionPeriod));
    }

    // Confirm that an auction cannot be settled prematurely
    function test012() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.prank(alice);
        auction.bid{value: reservePrice}(auctionId, reservePrice);

        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAuction.AuctionStillActive.selector));
        auction.settleAuction(auctionId);
    }

    // Confirm that an auction can be settled once time has passed the endTime
    function test013() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.prank(alice);
        auction.bid{value: reservePrice}(auctionId, reservePrice);

        vm.warp(block.timestamp + 6 hours);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionSettled(auctionId);
        auction.settleAuction(auctionId); // No need for prank, anyone can call settleAuction

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.SETTLED);
        assert(address(auction).balance == 0);
        assert(seller.balance == startingCurrencyAmount * 1 ether + reservePrice);
        assert(alice.balance == startingCurrencyAmount * 1 ether - reservePrice);
        assert(mockErc721.ownerOf(0) == alice);
    }

    // Confirm that an auction with no bids can be cancelled by the seller
    function test014() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionCancelled(auctionId);
        auction.cancelAuction(auctionId);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.CANCELLED);
        assert(address(auction).balance == 0);
        assert(seller.balance == startingCurrencyAmount * 1 ether);
        assert(mockErc721.ownerOf(0) == seller);
    }

    // Confirm that an auction with bids cannot be cancelled by the seller
    function test015() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.prank(alice);
        auction.bid{value: reservePrice}(auctionId, reservePrice);

        vm.startPrank(seller);
        vm.expectRevert(IAuction.BidsAlreadyMade.selector);
        auction.cancelAuction(auctionId);
    }

    // Confirm that an auction with no bids can be settled by anyone after the endTime
    function test016() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.warp(block.timestamp + 6 hours);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionSettled(auctionId);
        auction.settleAuction(auctionId); // No need for prank, anyone can call settleAuction

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.SETTLED);
        assert(mockErc721.ownerOf(0) == seller);
    }

    // Same as test013 but for ERC1155
    function test017() external {
        uint256 erc1155ListingAmount = 10;
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc1155), 0, erc1155ListingAmount, IAuction.TOKEN_TYPE.ERC1155, address(0));
        vm.stopPrank();

        vm.prank(alice);
        auction.bid{value: reservePrice}(auctionId, reservePrice);

        vm.warp(block.timestamp + 6 hours);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionSettled(auctionId);
        auction.settleAuction(auctionId); // No need for prank, anyone can call settleAuction

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.SETTLED);
        assert(address(auction).balance == 0);
        assert(seller.balance == startingCurrencyAmount * 1 ether + reservePrice);
        assert(alice.balance == startingCurrencyAmount * 1 ether - reservePrice);
        assert(mockErc1155.balanceOf(alice, 0) == erc1155ListingAmount);
    }

    // Same as test014 but for ERC1155
    function test018() external {
        uint256 erc1155ListingAmount = 10;
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc1155), 0, 1, IAuction.TOKEN_TYPE.ERC1155, address(0));
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionCancelled(auctionId);
        auction.cancelAuction(auctionId);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.CANCELLED);
        assert(address(auction).balance == 0);
        assert(seller.balance == startingCurrencyAmount * 1 ether);
        assert(mockErc1155.balanceOf(seller, 0) == erc1155ListingAmount);
    }

    // Same as test016 but for ERC1155
    function test019() external {
        uint256 erc1155ListingAmount = 10;
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc1155), 0, erc1155ListingAmount, IAuction.TOKEN_TYPE.ERC1155, address(0));
        vm.stopPrank();

        vm.warp(block.timestamp + 6 hours);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionSettled(auctionId);
        auction.settleAuction(auctionId);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.SETTLED);
        assert(mockErc1155.balanceOf(seller, 0) == erc1155ListingAmount);
    }

    // Same as test010 but with ERC20 instead of native ETH
    function test020() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(mockErc20));
        vm.stopPrank();

        uint256 bidAmount = reservePrice;
        vm.prank(alice);
        auction.bid(auctionId, bidAmount);

        vm.startPrank(bob);
        bidAmount = bidAmount + 0.1 ether; // Needs to be at least 10.1 MockErc20 (+ 1%) to be valid
        vm.expectEmit(address(auction));
        emit IAuction.NewBid(auctionId, bob, bidAmount);
        auction.bid(auctionId, bidAmount);

        IAuction.AuctionParams memory listing = auction.getAuction(auctionId);
        assert(listing.winningBid.bidder == payable(bob));
        assert(listing.winningBid.amount == bidAmount);
        assert(mockErc20.balanceOf(address(auction)) == bidAmount);
        assert(mockErc20.balanceOf(alice) == startingCurrencyAmount * 1 ether);
        assert(mockErc20.balanceOf(bob) == startingCurrencyAmount * 1 ether - bidAmount);
    }

    // Same as test013 but with ERC20 instead of native ETH
    function test021() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(mockErc20));
        vm.stopPrank();

        vm.prank(alice);
        auction.bid(auctionId, reservePrice);

        vm.warp(block.timestamp + 6 hours);
        vm.expectEmit(address(auction));
        emit IAuction.AuctionSettled(auctionId);
        auction.settleAuction(auctionId);

        IAuction.AuctionParams memory listing = auction.getAuction(0);
        assert(listing.status == IAuction.STATUS.SETTLED);
        assert(mockErc20.balanceOf(address(auction)) == 0);
        assert(mockErc20.balanceOf(seller) == reservePrice);
        assert(mockErc20.balanceOf(alice) == startingCurrencyAmount * 1 ether - reservePrice);
        assert(mockErc721.ownerOf(0) == alice);
    }

    // Test that multiple auctions can be created by the seller
    function test022() external {
        uint256 erc1155ListingAmount = 5;
        vm.startPrank(seller);

        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        assert(auction.getLifetimeAuctionsCreated() == 1);
        auctionId++; // Update this here to to make sure the event check in _createAuctionAndTestEvent aligns to correct value

        _createAuctionAndTestEvent(address(mockErc721), 1, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        assert(auction.getLifetimeAuctionsCreated() == 2);
        auctionId++;

        _createAuctionAndTestEvent(address(mockErc1155), 0, erc1155ListingAmount, IAuction.TOKEN_TYPE.ERC1155, address(0));
        assert(auction.getLifetimeAuctionsCreated() == 3);
        auctionId++;

        _createAuctionAndTestEvent(address(mockErc1155), 1, erc1155ListingAmount, IAuction.TOKEN_TYPE.ERC1155, address(0));
        assert(auction.getLifetimeAuctionsCreated() == 4);
    }

    // Test that the seller can update the minBidIncrementBps
    function test023() external {
        uint256 newMinBidIncrementBps = 200; // 2%
        vm.startPrank(seller);
        auction.setMinBidIncrementBps(newMinBidIncrementBps);
        assert(auction.getMinBidIncrementBps() == newMinBidIncrementBps);
    }

    // Test that the seller can update the softClosePeriod
    function test024() external {
        uint32 newSoftClosePeriod = 5 minutes;
        vm.startPrank(seller);
        auction.setSoftClosePeriod(newSoftClosePeriod);
        assert(auction.getSoftClosePeriod() == newSoftClosePeriod);
    }

    // Test that the seller can update the auctionExtensionPeriod
    function test025() external {
        uint32 newAuctionExtensionPeriod = 5 minutes;
        vm.startPrank(seller);
        auction.setAuctionExtensionPeriod(newAuctionExtensionPeriod);
        assert(auction.getAuctionExtensionPeriod() == newAuctionExtensionPeriod);
    }

    // Test that a new auction cannot be created if the endTime is in the past
    function test026() external {
        vm.startPrank(seller);
        uint256 endTime = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidAuctionEndtime.selector, endTime));
        auction.createAuction(IAuction.AuctionInputs({
            endTime: uint32(endTime),
            nftAddress: address(mockErc721),
            nftTokenId: 0,
            nftAmount: 1,
            currencyAddress: address(0),
            reservePrice: reservePrice
        }));
    }

    // Test that only ERC721 and ERC1155 are supported
    function test027() external {
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAuction.UnsupportedTokenType.selector, address(mockErc20)));

        auction.createAuction(IAuction.AuctionInputs({
            endTime: uint32(block.timestamp + auctionDuration),
            nftAddress: address(mockErc20), // We use the mock ERC20 here to test the revert, but it could be any non-supported address
            nftTokenId: 0,
            nftAmount: 1,
            currencyAddress: address(0),
            reservePrice: reservePrice
        }));
    }

    // Test that ERC721 listings cannot be created if amount is not 1
    function test028() external {
        uint256 incorrectAmount = 2;
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidNftAmount.selector, incorrectAmount));

        auction.createAuction(IAuction.AuctionInputs({
            endTime: uint32(block.timestamp + auctionDuration),
            nftAddress: address(mockErc721),
            nftTokenId: 0,
            nftAmount: incorrectAmount,
            currencyAddress: address(0),
            reservePrice: reservePrice
        }));
    }

    // Test that ERC1155 listings cannot be created if amount is 0
    function test029() external {
        uint256 incorrectAmount = 0;
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidNftAmount.selector, incorrectAmount));

        auction.createAuction(IAuction.AuctionInputs({
            endTime: uint32(block.timestamp + auctionDuration),
            nftAddress: address(mockErc1155),
            nftTokenId: 0,
            nftAmount: incorrectAmount,
            currencyAddress: address(0),
            reservePrice: reservePrice
        }));
    }

    // Test that a bid cannot be made after the auction's endTime, even if it is not settled yet
    function test030() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAuction.AuctionEnded.selector));
        auction.bid{value: reservePrice}(auctionId, reservePrice);
    }

    // Test that an ETH bid must send the correct amount of ETH
    function test031() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(0));

        vm.startPrank(alice);
        uint256 bidAmount = reservePrice;
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidEthAmount.selector, bidAmount * 2));
        auction.bid{value: bidAmount}(auctionId, bidAmount * 2);
    }

    // Test that no ETH is sent when making erc20 bids
    function test032() external {
        vm.startPrank(seller);
        _createAuctionAndTestEvent(address(mockErc721), 0, 1, IAuction.TOKEN_TYPE.ERC721, address(mockErc20));

        vm.startPrank(alice);
        uint256 bidAmount = reservePrice;
        vm.expectRevert(abi.encodeWithSelector(IAuction.InvalidEthAmount.selector, bidAmount));
        auction.bid{value: 1 wei}(auctionId, bidAmount);
    }

    function _deploy() private {
        mockErc20 = new MockERC20();
        mockErc721 = new MockERC721();
        mockErc1155 = new MockERC1155("someUri");
        vm.prank(seller);
        auction = new Auction(minBidIncrementBps, softClosePeriod, auctionExtensionPeriod);
    }

    function _mintInitialTokens() private {
        // Give some erc20 tokens to buyers
        deal(address(mockErc20), alice, 10000 ether);
        deal(address(mockErc20), bob, 10000 ether);

        // Give nfts to seller
        mockErc721.mint(seller, 0); // 1 of tokenId 0
        mockErc721.mint(seller, 1); // 1 of tokenId 1
        mockErc1155.mint(seller, 0, 10); // 10 of tokenId 0
        mockErc1155.mint(seller, 1, 10); // 10 of tokenId 1

        // Do all token approvals
        vm.prank(alice);
        mockErc20.approve(address(auction), 10000 ether);
        vm.prank(bob);
        mockErc20.approve(address(auction), 10000 ether);
        vm.startPrank(seller);
        mockErc721.setApprovalForAll(address(auction), true);
        mockErc1155.setApprovalForAll(address(auction), true);
        vm.stopPrank();
    }

    function _createAuctionAndTestEvent(address nftAddress, uint256 nftTokenId, uint256 nftAmount, IAuction.TOKEN_TYPE nftType, address currencyAddress) private {
        vm.expectEmit(address(auction));

        emit IAuction.AuctionCreated(auctionId, IAuction.AuctionParams({
            endTime: uint32(block.timestamp + auctionDuration),
            currencyAddress: currencyAddress,
            seller: seller,
            nftAddress: nftAddress,
            nftTokenId: nftTokenId,
            nftAmount: nftAmount,
            reservePrice: reservePrice,
            winningBid: IAuction.Bid({
                bidder: payable(address(0)),
                amount: 0
            }),
            tokenType: nftType,
            status: IAuction.STATUS.ACTIVE
        }));

        auction.createAuction(IAuction.AuctionInputs({
            endTime: uint32(block.timestamp + auctionDuration),
            nftAddress: nftAddress,
            nftTokenId: nftTokenId,
            nftAmount: nftAmount,
            currencyAddress: currencyAddress,
            reservePrice: reservePrice
        }));
    }
}
