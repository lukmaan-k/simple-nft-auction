// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Auction.sol";


contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ANVIL");
        vm.startBroadcast(deployerPrivateKey);

        uint256 minBidIncrementBps = 100; // 1%
        uint32 softClosePeriod = 180; // 3 minutes
        uint32 auctionExtensionPeriod = 60; // 1 minute 

        new Auction(minBidIncrementBps, softClosePeriod, auctionExtensionPeriod);

        vm.stopBroadcast();
    }
}
