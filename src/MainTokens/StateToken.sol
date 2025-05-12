// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract STATE_Token_V2_1_Ratio_Swapping is ERC20 {
    uint256 public constant MAX_SUPPLY = 1000000000000000 ether; // 1 QUADRILLION

    constructor(
        string memory name,
        string memory symbol,
        address _five,
        address _swap
    ) ERC20(name, symbol) {
        require(_five != address(0) && _swap != address(0), "Invalid address");

        uint256 Five_percent = (MAX_SUPPLY * 5) / 100;
        uint256 ninetyFivePercent = MAX_SUPPLY - Five_percent;
        _mint(_five, Five_percent);
        _mint(_swap, ninetyFivePercent);
    }
}
