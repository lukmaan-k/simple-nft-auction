// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


interface IAuction {
    enum STATUS {
        __, // Skip default value
        CANCELLED,
        ACTIVE,
        SETTLED
    }

    enum TOKEN_TYPE {
        ERC721,
        ERC1155
    }

    struct AuctionInputs {
        uint32 endTime;
        address nftAddress;
        uint256 nftTokenId;
        uint256 nftAmount; 
        address currencyAddress; 
        uint256 reservePrice; 
    }

    struct Bid {
        address payable bidder;
        uint256 amount;
    }

    struct AuctionParams {
        uint32 endTime;
        address currencyAddress; 
        address seller;
        address nftAddress;
        uint256 nftTokenId;
        uint256 nftAmount;
        uint256 reservePrice;
        Bid winningBid;
        TOKEN_TYPE tokenType;
        STATUS status;
    }

    event NewBid(uint256 indexed auctionId, address indexed bidder, uint256 indexed amount);
    event AuctionCreated(uint256 indexed auctionId, AuctionParams auction);
    event AuctionCancelled(uint256 indexed auctionId);
    event AuctionSettled(uint256 indexed auctionId);
    event MinBidIncrementBpsUpdated(uint256 newMinBidIncrementBps);
    event SoftClosePeriodUpdated(uint32 newSoftClosePeriod);
    event AuctionExtensionPeriodUpdated(uint32 newAuctionExtensionPeriod);

    error InvalidAuctionId(uint256 auctionId);
    error InvalidBidAmount(uint256 amount);
    error InvalidAuctionEndtime(uint256 endTime);
    error UnsupportedTokenType(address nftAddress);
    error InvalidNftAmount(uint256 amount);
    error AuctionEnded();
    error AuctionStillActive();
    error InvalidEthAmount(uint256 amount);
    error BidsAlreadyMade();
}
