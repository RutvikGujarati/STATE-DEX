// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UserToken is ERC20, Ownable(msg.sender) {
    uint256 public constant MAX_SUPPLY = 500000000000 ether; // 500 billion

    constructor(
        string memory name,
        string memory symbol,
        address _One,
        address _swap
    ) ERC20(name, symbol)  {
        require(_One != address(0) && _swap != address(0), "Invalid address");

        uint256 One_percent = (MAX_SUPPLY * 1) / 100;
        uint256 ninetyNinePercent = MAX_SUPPLY - One_percent;
        _mint(_One, One_percent);
        _mint(_swap, ninetyNinePercent);
    }
}
