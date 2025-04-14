// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract STATE_Token_V2_1_Ratio_Swapping is ERC20, Ownable(msg.sender) {
    uint256 public constant MAX_SUPPLY = 1000000000000000 ether; // 1 QUADRILLION

    constructor(
        string memory name,
        string memory symbol,
        address _five,
        address _stateLp
    ) ERC20(name, symbol) {
        require(
            _five != address(0) && _stateLp != address(0),
            "Invalid address"
        );

        uint256 Five_percent = (MAX_SUPPLY * 5) / 100;
        uint256 ninetyFivePercent = MAX_SUPPLY - Five_percent;
        _mint(_five, Five_percent);
        _mint(_stateLp, ninetyFivePercent);
    }
}
