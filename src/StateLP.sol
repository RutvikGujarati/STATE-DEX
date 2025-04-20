// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StateLP {
    using SafeERC20 for IERC20;

    IERC20 public stateToken;
    IERC20 public davToken;

    address public Governance;
    address public stateAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;
    uint256 public constant MIN_DAV = 1 * 1e18;
    uint256 public constant MONTH = 30 days; // Approximate month length
    uint256 public constant YEAR = 365 days; // Approximate year length

    struct BurnInfo {
        uint256 totalBurned; // User's total burned STATE tokens
        uint256 lastClaimed; // Timestamp of last claim
        uint256 userShare; // User's share of total burned tokens (scaled by 1e18)
    }

    uint256 public totalStateBurned; // Total STATE tokens burned by all users
    mapping(address => BurnInfo) public userBurns;

    constructor(address _state, address _governance) {
        stateToken = IERC20(_state);
        stateAddress = _state;
        Governance = _governance;
    }

    modifier onlyGovernance() {
        require(msg.sender == Governance, "Not authorized");
        _;
    }

    function depositPLS() external payable onlyGovernance {
        require(msg.value > 0, "Must send PLS");
    }

    function addDavToken(address _dav) public onlyGovernance {
        davToken = IERC20(_dav);
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

        BurnInfo storage burnInfo = userBurns[msg.sender];

        totalStateBurned += amount;
        burnInfo.totalBurned += amount;

        // Prevent division by zero
        burnInfo.userShare = (burnInfo.totalBurned * 1e18) / totalStateBurned;

        // Only set if first time
        // burnInfo.lastClaimed = getPreviousMonth19th();

        stateToken.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
    }

    function getPreviousMonth19th() public view returns (uint256) {
        (uint256 year, uint256 month, ) = timestampToDate(block.timestamp);

        if (month == 1) {
            year -= 1;
            month = 12;
        } else {
            month -= 1;
        }

        return timestampFromDate(year, month, 19);
    }

    function getCurrentMonth15th() public view returns (uint256) {
        // Get the current timestamp in UTC
        (uint256 year, uint256 month, ) = timestampToDate(block.timestamp);
        return timestampFromDate(year, month, 19);
    }

    // Adapted from BokkyPooBah's DateTime Library
    function isLeapYear(uint256 year) internal pure returns (bool) {
        return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
    }

    function getCurrentMonthNumber() public view returns (uint256) {
        (, uint256 month, ) = timestampToDate(block.timestamp);
        return month;
    }

    function getCurrentDayOfMonth() public view returns (uint256) {
        (, , uint256 day) = timestampToDate(block.timestamp);
        return day;
    }

    function _daysInMonth(
        uint256 month,
        uint256 year
    ) internal pure returns (uint8) {
        if (month == 2) {
            return isLeapYear(year) ? 29 : 28;
        } else if (
            month == 1 ||
            month == 3 ||
            month == 5 ||
            month == 7 ||
            month == 8 ||
            month == 10 ||
            month == 12
        ) {
            return 31;
        } else {
            return 30;
        }
    }

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

    function timestampFromDate(
        uint256 year,
        uint256 month,
        uint256 day
    ) public pure returns (uint256 timestamp) {
        uint256 y = year;
        uint256 m = month;
        uint256 d = day;
        require(y >= 1970);
        int256 _days = int256(
            d -
                32075 +
                (1461 * (y + 4800 + (m - 14) / 12)) /
                4 +
                (367 * (m - 2 - ((m - 14) / 12) * 12)) /
                12 -
                (3 * ((y + 4900 + (m - 14) / 12) / 100)) /
                4 -
                2440588
        );
        timestamp = uint256(_days) * 86400;
    }

    // Helper function to get the timestamp of the 15th of the next month
    function getNextMonth15th() public view returns (uint256) {
        return getCurrentMonth15th() + MONTH;
    }

    // Helper function to check if current date is on or after the 15th of the month
    function isOnOrAfter20th() public view returns (bool) {
        return getCurrentDayOfMonth() >= 20;
    }

    // Helper function to check if current date is within the same month as a given timestamp
    function isSameMonth(uint256 timestamp) public view returns (bool) {
        uint256 currentMonthStart = (block.timestamp / MONTH) * MONTH;
        uint256 givenMonthStart = (timestamp / MONTH) * MONTH;
        return currentMonthStart == givenMonthStart;
    }

    function getRemainingClaimablePLS(
        address user
    ) public view returns (uint256) {
        BurnInfo memory burnInfo = userBurns[user];
        if (burnInfo.totalBurned == 0 || burnInfo.userShare == 0) return 0;

        // Check if user has already claimed this month
        if (isSameMonth(burnInfo.lastClaimed)) {
            return 0;
        }

        // Total PLS available to distribute (50% of contract balance)
        uint256 availablePLS = address(this).balance / 2;
        if (availablePLS == 0) return 0;

        // Monthly distribution
        uint256 monthlyPLS = availablePLS / 12;

        // User's monthly share based on their userShare
        uint256 monthlyUserReward = (monthlyPLS * burnInfo.userShare) / 1e18;

        return monthlyUserReward;
    }

    function claimPLS() external {
        BurnInfo storage burnInfo = userBurns[msg.sender];
        require(burnInfo.totalBurned > 0, "No STATE burned");
        require(isOnOrAfter20th(), "Claims only allowed on or after the 20th");

        (, uint256 lastClaimMonth, ) = timestampToDate(burnInfo.lastClaimed);
        uint256 currentMonth = getCurrentMonthNumber();
        require(lastClaimMonth != currentMonth, "Already claimed this month");

        // Total PLS available to distribute (50% of contract balance)
        uint256 availablePLS = address(this).balance / 2;
        require(availablePLS > 0, "No PLS available");

        // Monthly distribution
        uint256 monthlyPLS = availablePLS / 12;

        // User's monthly share based on their userShare
        uint256 monthlyUserReward = (monthlyPLS * burnInfo.userShare) / 1e18;
        require(monthlyUserReward > 0, "Nothing to claim");

        // Update lastClaimed to current timestamp
        burnInfo.lastClaimed = block.timestamp;

        // Transfer PLS to user
        (bool success, ) = payable(msg.sender).call{value: monthlyUserReward}(
            ""
        );
        require(success, "PLS transfer failed");
    }

    function nextClaimDate(address user) external view returns (uint256) {
        BurnInfo memory burn = userBurns[user];

        (, uint256 currentMonth, ) = timestampToDate(block.timestamp);
        (, uint256 lastClaimMonth, ) = timestampToDate(burn.lastClaimed);

        if (burn.lastClaimed == 0 || lastClaimMonth != currentMonth) {
            // User hasn't claimed this month
            return
                timestampFromDate(
                    block.timestamp / 365 days + 1970,
                    currentMonth,
                    20
                );
        }

        // Next month
        uint256 year;
        uint256 nextMonth;
        if (currentMonth == 12) {
            year = (block.timestamp / YEAR) + 1971;
            nextMonth = 1;
        } else {
            year = (block.timestamp / YEAR) + 1970;
            nextMonth = currentMonth + 1;
        }

        return timestampFromDate(year, nextMonth, 20);
    }

    function canClaimNow(address user) external view returns (bool) {
        BurnInfo memory burn = userBurns[user];
        if (burn.totalBurned == 0) return false;

        (, uint256 lastClaimMonth, ) = timestampToDate(burn.lastClaimed);
        uint256 currentMonth = getCurrentMonthNumber();

        return isOnOrAfter20th() && lastClaimMonth != currentMonth;
    }

    function getContractPLSBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}

    fallback() external payable {}
}
