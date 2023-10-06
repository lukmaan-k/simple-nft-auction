// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IAuction.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Auction is ERC721Holder, ERC1155Holder, IAuction, Ownable {
    using Counters for Counters.Counter;

    uint256 private constant MIN_BID_INCREMENT_DENOM = 10000;   // denominator for _minBidIncrementPercent
    uint256 private _minBidIncrementBps;                        // Bids must be greater than X% of the current winning bid.
    uint32 private _softClosePeriod;                            // Bids in the last 3 minutes will extend the auction.
    uint32 private _auctionExtensionPeriod;                     // How long to extend the auction when bids are placed in the final minutes.

    mapping(uint256 => IAuction.AuctionParams) private auctions;
    Counters.Counter private _auctionIds;

    modifier onlyActiveAuction(uint256 auctionId) {
        if (auctions[auctionId].status != IAuction.STATUS.ACTIVE) revert InvalidAuctionId(auctionId);
        _;
    }

    constructor(uint256 minBidIncrementBps, uint32 softClosePeriod, uint32 auctionExtensionPeriod) {
        _minBidIncrementBps = minBidIncrementBps;
        _softClosePeriod = softClosePeriod;
        _auctionExtensionPeriod = auctionExtensionPeriod;
    }

    function createAuction(IAuction.AuctionInputs calldata inputs) external onlyOwner {

        if (inputs.endTime < block.timestamp) {
            revert InvalidAuctionEndtime(inputs.endTime);
        }

        IAuction.TOKEN_TYPE tokenType;
        if (IERC721(inputs.nftAddress).supportsInterface(type(IERC721).interfaceId)) {
            if (inputs.nftAmount != 1) revert InvalidNftAmount(inputs.nftAmount);
        } else if (IERC1155(inputs.nftAddress).supportsInterface(type(IERC1155).interfaceId)) {
            if (inputs.nftAmount == 0) revert InvalidNftAmount(inputs.nftAmount);
            tokenType = IAuction.TOKEN_TYPE.ERC1155; // Update to ERC1155. Default value is already TOKEN_TYPE.ERC721 so no need to update above
        } else {
            revert UnsupportedTokenType(inputs.nftAddress); // This doesn't hit if the contract doesn't implement supportsInterface(), and reverts without a reason
        }
        
        _transferNFT(inputs.nftAddress, inputs.nftTokenId, inputs.nftAmount, msg.sender, address(this), tokenType);
        
        IAuction.AuctionParams memory newAuction = IAuction.AuctionParams({
            endTime: inputs.endTime,
            currencyAddress: inputs.currencyAddress,
            seller: msg.sender,
            nftAddress: inputs.nftAddress,
            nftTokenId: inputs.nftTokenId,
            nftAmount: inputs.nftAmount,
            reservePrice: inputs.reservePrice,
            winningBid: IAuction.Bid({
                bidder: payable(address(0)),
                amount: 0
            }),
            tokenType: tokenType,
            status: IAuction.STATUS.ACTIVE
        });

        auctions[_auctionIds.current()] = newAuction;

        emit AuctionCreated(_auctionIds.current(), newAuction);

        _auctionIds.increment();
    }

    function bid(uint256 auctionId, uint256 amount) external payable onlyActiveAuction(auctionId) {
        // Copying the 3 variables below is more efficient than using a pointer to the AuctionParams struct
        uint32 endTime = auctions[auctionId].endTime;
        address currencyAddress = auctions[auctionId].currencyAddress;
        uint256 reservePrice = auctions[auctionId].reservePrice;
        if (block.timestamp >= endTime) revert AuctionEnded();

        IAuction.Bid memory previousWinningBid = auctions[auctionId].winningBid;
        uint256 minNewBid = previousWinningBid.amount + previousWinningBid.amount * _minBidIncrementBps / MIN_BID_INCREMENT_DENOM;
        
        if (amount < minNewBid || amount < reservePrice) revert InvalidBidAmount(amount); // The second conditional becomes redundant after the first successful bid

        if (currencyAddress == address(0) && msg.value != amount) { // For listings wanting ETH, the amount sent must match the bid amount
            revert InvalidEthAmount(amount);
        } else if (currencyAddress != address(0)) { // For listings wanting tokens
            if (msg.value > 0) revert InvalidEthAmount(amount); // Don't send unwanted ETH
            _transferCurrency(currencyAddress, amount, msg.sender, address(this));
        }

        if (block.timestamp >= endTime - _softClosePeriod) { // prevent last second sniping
            auctions[auctionId].endTime = endTime + _auctionExtensionPeriod;
        }

        auctions[auctionId].winningBid = IAuction.Bid({
            bidder: payable(msg.sender),
            amount: amount
        });

        if (previousWinningBid.bidder != address(0)) { // Return losing bidder's funds
            _transferCurrency(currencyAddress, previousWinningBid.amount, address(this), previousWinningBid.bidder);
        }

        emit NewBid(auctionId, msg.sender, amount);
    }

    function cancelAuction(uint256 auctionId) external onlyOwner onlyActiveAuction(auctionId) {
        IAuction.AuctionParams storage auction = auctions[auctionId];
        if (auction.winningBid.bidder != address(0)) {
            revert BidsAlreadyMade();
        }

        _transferNFT(auction.nftAddress, auction.nftTokenId, auction.nftAmount, address(this), auction.seller, auction.tokenType);

        auction.status = IAuction.STATUS.CANCELLED;

        emit AuctionCancelled(auctionId);
    }

    function settleAuction(uint256 auctionId) external onlyActiveAuction(auctionId) {
        IAuction.AuctionParams storage auction = auctions[auctionId];
        IAuction.Bid memory winningBid = auctions[auctionId].winningBid;
        if (block.timestamp < auction.endTime) revert AuctionStillActive();

        auction.status = IAuction.STATUS.SETTLED; // Update state here to prevent reentrancy

        if (winningBid.bidder == address(0)) {
            _transferNFT(auction.nftAddress, auction.nftTokenId, auction.nftAmount, address(this), auction.seller, auction.tokenType);
        } else {
            _transferCurrency(auction.currencyAddress, winningBid.amount, address(this), auction.seller);
            _transferNFT(auction.nftAddress, auction.nftTokenId, auction.nftAmount, address(this), winningBid.bidder, auction.tokenType);
        }

        emit AuctionSettled(auctionId);
    }

    function getLifetimeAuctionsCreated() external view returns (uint256) {
        return _auctionIds.current();
    }

    function getAuction(uint256 auctionId) external view returns (IAuction.AuctionParams memory) {
        return auctions[auctionId];
    }

    function getMinBidIncrementBps() external view returns (uint256) {
        return _minBidIncrementBps;
    }

    function getSoftClosePeriod() external view returns (uint32) {
        return _softClosePeriod;
    }

    function getAuctionExtensionPeriod() external view returns (uint32) {
        return _auctionExtensionPeriod;
    }

    function setMinBidIncrementBps(uint256 minBidIncrementBps) external onlyOwner {
        _minBidIncrementBps = minBidIncrementBps;
        emit MinBidIncrementBpsUpdated(minBidIncrementBps);
    }

    function setSoftClosePeriod(uint32 softClosePeriod) external onlyOwner {
        _softClosePeriod = softClosePeriod;
        emit SoftClosePeriodUpdated(softClosePeriod);
    }

    function setAuctionExtensionPeriod(uint32 auctionExtensionPeriod) external onlyOwner {
        _auctionExtensionPeriod = auctionExtensionPeriod;
        emit AuctionExtensionPeriodUpdated(auctionExtensionPeriod);
    }

    function _transferNFT(address nftAddress, uint256 tokenId, uint256 amount, address from, address to, IAuction.TOKEN_TYPE tokenType) private {        
        if(tokenType == IAuction.TOKEN_TYPE.ERC721) {
            IERC721(nftAddress).safeTransferFrom(from, to, tokenId, "");
        } else if(tokenType == IAuction.TOKEN_TYPE.ERC1155) {
            IERC1155(nftAddress).safeTransferFrom(from, to, tokenId, amount, "");
        } else revert UnsupportedTokenType(nftAddress); // this should never reach
    }

    function _transferCurrency(address currencyAddress, uint256 amount, address from, address to) private {
        if(currencyAddress == address(0)) {
            payable(to).transfer(amount);
        } else {
            if (from == address(this)) {
                IERC20(currencyAddress).transfer(to, amount);
            } else {
                IERC20(currencyAddress).transferFrom(from, to, amount);
            }
        }   
    }
}
