// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

contract StateLP {
    using SafeERC20 for IERC20;

    IERC20 public stateToken;
    IERC20 public davToken;

    address public Governance;
    address public pairAddress;
    address public Wpls;
    address public stateAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;
    uint256 public constant MIN_DAV = 25 * 1e18;
    uint256 public constant MIN_BURN = 1000000000 * 1e18;
    uint256 public constant CLAIM_INTERVAL = 30 days;

    struct BurnInfo {
        uint256 totalBurned;
        bool hasClaimed;
        uint256 lastClaimed;
    }

    mapping(address => BurnInfo) public userBurns;

    constructor(
        address _state,
        address _wpls,
        address _pairAddress,
        address _governance
    ) {
        stateToken = IERC20(_state);
        stateAddress = _state;
        Wpls = _wpls;
        Governance = _governance;
        pairAddress = _pairAddress;
    }

    modifier onlyGovernance() {
        require(msg.sender == Governance, "Not authorized");
        _;
    }

    function getRatioPrice() public view returns (uint256) {
        IPair pair = IPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(reserve0 > 0 && reserve1 > 0, "Invalid reserves");

        uint256 ratio;
        if (token0 == Wpls && token1 == stateAddress) {
            ratio = (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else if (token0 == stateAddress && token1 == Wpls) {
            ratio = (uint256(reserve0) * 1e18) / uint256(reserve1);
        } else {
            revert("Invalid pair");
        }

        return ratio;
    }

    function depositPLS() external payable onlyGovernance {
        require(msg.value > 0, "Must send PLS");
    }

    function addDavToken(address _dav) public onlyGovernance {
        davToken = IERC20(payable(_dav));
    }

    function burnState(uint256 amount) external {
        require(
            davToken.balanceOf(msg.sender) >= MIN_DAV,
            "You need more than 50 DAV"
        );
        require(
            amount % MIN_BURN == 0,
            "Amount must be in 1B STATE increments"
        );

        stateToken.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);

        BurnInfo storage burnInfo = userBurns[msg.sender];
        burnInfo.totalBurned += amount;
    }

    function claimPLS(uint256 _stateWplsRatio) external {
        BurnInfo storage burnInfo = userBurns[msg.sender];

        require(burnInfo.totalBurned > 0, "No STATE burned");
        require(
            block.timestamp >= burnInfo.lastClaimed + CLAIM_INTERVAL,
            "Claim interval not yet passed"
        );

        uint256 value = (burnInfo.totalBurned * _stateWplsRatio * 2) / 1e18;

        require(address(this).balance >= value, "Not enough PLS in contract");

        burnInfo.lastClaimed = block.timestamp;
        burnInfo.hasClaimed = true;

        burnInfo.totalBurned = 0; // Reset burn amount after claim

        (bool success, ) = payable(msg.sender).call{value: value}("");
        require(success, "PLS transfer failed");
    }

    function nextClaimDate(address user) external view returns (uint256) {
        BurnInfo memory burn = userBurns[user];
        if (burn.lastClaimed == 0) return 0;
        return burn.lastClaimed + CLAIM_INTERVAL;
    }

    function canClaimNow(address user) external view returns (bool) {
        BurnInfo memory burn = userBurns[user];
        return block.timestamp >= burn.lastClaimed + CLAIM_INTERVAL;
    }

    receive() external payable {}

    fallback() external payable {}

    function getContractPLSBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
