// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StateLP {
    using SafeERC20 for IERC20;

    IERC20 public stateToken;
    IERC20 public davToken;

    address public stateAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;

    uint256 public constant MIN_DAV = 1 * 1e18;

    struct BurnInfo {
        uint256 totalBurned;
        uint256 lastClaimedMonth;
        uint256 userShare; // Scaled by 1e18
    }
    struct UserBurn {
        uint256 amount; // Amount of STATE burned
        uint256 totalAtTime; // Total STATE burned at the time
        uint256 timestamp; // Burn timestamp
        bool[12] claimedMonths; // Claim status for each of the 12 months
    }

    mapping(address => UserBurn[]) public burnHistory;

    uint256 public totalStateBurned;
    mapping(address => BurnInfo) public userBurns;

    constructor(address _state) {
        stateToken = IERC20(_state);
        stateAddress = _state;
    }

    function burnState(uint256 amount) external {
        require(address(davToken) != address(0), "DAV token not set");
        require(
            davToken.balanceOf(msg.sender) >= MIN_DAV,
            "Need at least 1 DAV"
        );
        require(amount > 0, "Burn amount must be > 0");
        require(
            stateToken.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        stateToken.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);

        totalStateBurned += amount;

        // Record snapshot
        burnHistory[msg.sender].push(
            UserBurn({
                amount: amount,
                totalAtTime: totalStateBurned,
                timestamp: block.timestamp,
                claimedMonths: [
                    false,
                    false,
                    false,
                    false,
                    false,
                    false,
                    false,
                    false,
                    false,
                    false,
                    false,
                    false
                ]
            })
        );
    }

    function getCurrentMonthNumber() public view returns (uint256) {
        (, uint256 month, ) = timestampToDate(block.timestamp);
        return month;
    }

    function getCurrentDayOfMonth() public view returns (uint256) {
        (, , uint256 day) = timestampToDate(block.timestamp);
        return day;
    }

    function isOnOrAfter20th() public view returns (bool) {
        return getCurrentDayOfMonth() >= 20;
    }

    function canClaimNow(address user) external view returns (bool) {
        BurnInfo memory burn = userBurns[user];
        if (burn.totalBurned == 0) return false;

        uint256 currentMonth = getCurrentMonthNumber();
        return isOnOrAfter20th() && (burn.lastClaimedMonth < currentMonth);
    }

    function canClaim(address user) public view returns (bool) {
        BurnInfo memory info = userBurns[user];
        uint256 day = getCurrentDayOfMonth();

        // Can only claim on or after 20th, and only once per month
        return (day >= 20 && info.lastClaimedMonth != getCurrentMonthNumber());
    }

    function getRemainingClaimablePLS(
        address user
    ) public view returns (uint256) {
        UserBurn[] storage burns = burnHistory[user];
        if (burns.length == 0) return 0;

        uint256 totalReward = 0;
        uint256 availablePLS = address(this).balance / 2;
        uint256 monthlyPLS = availablePLS / 12;

        for (uint256 i = 0; i < burns.length; i++) {
            UserBurn storage burn = burns[i];

            for (uint256 j = 0; j < 12; j++) {
                uint256 eligibleMonth = getMonthFromTimestamp(burn.timestamp) +
                    j;
                if (
                    !burn.claimedMonths[j] &&
                    getCurrentMonthNumber() >= eligibleMonth
                ) {
                    // Calculate share for this month
                    uint256 share = (burn.amount * 1e18) / burn.totalAtTime;
                    uint256 reward = (monthlyPLS * share) / 1e18;
                    totalReward += reward;
                }
            }
        }

        return totalReward;
    }

    function getMissedMonthsAndUnclaimedPLS(
        address user
    ) external view returns (uint256 missedMonths, uint256 totalPLS) {
        BurnInfo memory burn = userBurns[user];
        if (burn.totalBurned == 0 || burn.userShare == 0) return (0, 0);

        uint256 currentMonth = getCurrentMonthNumber();
        if (burn.lastClaimedMonth >= currentMonth) return (0, 0);

        missedMonths = currentMonth - burn.lastClaimedMonth;
        uint256 availablePLS = address(this).balance / 2;
        uint256 monthlyPLS = availablePLS / 12;
        totalPLS = ((monthlyPLS * burn.userShare) / 1e18) * missedMonths;
    }

    function claimPLS() external {
        address user = msg.sender;
        UserBurn[] storage burns = burnHistory[user];
        require(burns.length > 0, "No burns found");

        uint256 totalReward = 0;
        uint256 availablePLS = address(this).balance / 2;
        uint256 monthlyPLS = availablePLS / 12;

        uint256 currentMonth = getCurrentMonthNumber();

        for (uint256 i = 0; i < burns.length; i++) {
            UserBurn storage burn = burns[i];

            for (uint256 j = 0; j < 12; j++) {
                uint256 eligibleMonth = getMonthFromTimestamp(burn.timestamp) +
                    j;

                if (!burn.claimedMonths[j] && currentMonth >= eligibleMonth) {
                    uint256 share = (burn.amount * 1e18) / burn.totalAtTime;
                    uint256 reward = (monthlyPLS * share) / 1e18;
                    totalReward += reward;
                    burn.claimedMonths[j] = true; // Mark this month's reward as claimed
                }
            }
        }

        require(totalReward > 0, "Nothing to claim");

        (bool success, ) = payable(user).call{value: totalReward}("");
        require(success, "PLS transfer failed");
    }

    function getMonthFromTimestamp(
        uint256 timestamp
    ) internal pure returns (uint256) {
        (, uint256 month, ) = timestampToDate(timestamp);
        return month;
    }

    function getContractPLSBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // --- Date Utility Functions ---

    function timestampToDate(
        uint256 timestamp
    ) public pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = (z >= 0 ? z : z - 146096) / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        day = doy - (153 * mp + 2) / 5 + 1;
        int256 _month = int256(mp) + (mp < 10 ? int256(3) : int256(-9));
        month = uint256(_month);
        year += (month <= 2 ? 1 : 0);
    }

    function getNextClaimDate(
        address user
    ) public view returns (string memory) {
        BurnInfo memory burn = userBurns[user];
        if (burn.totalBurned == 0) {
            return "No STATE burned";
        }

        uint256 currentMonth = getCurrentMonthNumber();
        uint256 nextMonth;

        if (burn.lastClaimedMonth == 0) {
            // User never claimed, next claim is current month if it's 20th or later
            if (getCurrentDayOfMonth() >= 20) {
                nextMonth = currentMonth;
            } else {
                nextMonth = currentMonth;
            }
        } else if (burn.lastClaimedMonth < currentMonth) {
            if (getCurrentDayOfMonth() >= 20) {
                nextMonth = currentMonth;
            } else {
                nextMonth = currentMonth;
            }
        } else {
            nextMonth = currentMonth + 1;
            if (nextMonth > 12) {
                nextMonth = 1;
            }
        }

        return string(abi.encodePacked("20 - ", monthNumberToName(nextMonth)));
    }

    function getUserSharePercentage(
        address user
    ) external view returns (uint256) {
        UserBurn[] memory burns = burnHistory[user];
        if (burns.length == 0) return 0;

        uint256 totalWeightedShare = 0;
        uint256 totalBurned = 0;

        for (uint256 i = 0; i < burns.length; i++) {
            if (burns[i].totalAtTime == 0) continue; // Avoid div by 0
            uint256 share = (burns[i].amount * 1e18) / burns[i].totalAtTime;
            totalWeightedShare += share * burns[i].amount;
            totalBurned += burns[i].amount;
        }

        if (totalBurned == 0) return 0;

        // Average share weighted by burned amount
        uint256 avgShare = totalWeightedShare / totalBurned;

        // Convert to percentage
        return (avgShare * 100) / 1e18;
    }

    function uintToString(uint256 v) internal pure returns (string memory str) {
        if (v == 0) {
            return "0";
        }
        uint256 maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint256 i = 0;
        while (v != 0) {
            uint256 remainder = v % 10;
            v = v / 10;
            reversed[i++] = bytes1(uint8(48 + remainder));
        }
        bytes memory s = new bytes(i);
        for (uint256 j = 0; j < i; j++) {
            s[j] = reversed[i - 1 - j];
        }
        str = string(s);
    }

    function monthNumberToName(
        uint256 month
    ) public pure returns (string memory) {
        string[12] memory months = [
            "January",
            "February",
            "March",
            "April",
            "May",
            "June",
            "July",
            "August",
            "September",
            "October",
            "November",
            "December"
        ];
        if (month >= 1 && month <= 12) {
            return months[month - 1];
        } else {
            return "Unknown";
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
