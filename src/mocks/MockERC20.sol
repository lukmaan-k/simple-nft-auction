// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MockERC20 is ERC20 {
    constructor() ERC20("MockERC20", "MOCK20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC20).interfaceId;
    }
}