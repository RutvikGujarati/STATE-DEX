// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

contract Ratio_Swapping_Auctions_V2_1 is Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public dav;
    uint256 public constant AUCTION_INTERVAL = 50 days;
    uint256 public constant REVERSE_AUCTION_INTERVAL = 200 days;
    uint256 public constant AUCTION_DURATION = 24 hours;
    uint256 public constant REVERSE_DURATION = 24 hours;
    uint256 public constant MAX_AUCTIONS = 56;
    uint256 public constant TIMEZONE_OFFSET = 19800; // GMT+5:30 in seconds (5.5 hours * 3600)
    uint256 public percentage = 1;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;

    address public stateToken;
    address public governanceAddress;
    mapping(address => address) public pairAddresses; // token => pair address
    mapping(address => bool) public supportedTokens; // token => isSupported
    mapping(address => uint256) public maxSupplies; // token => maxSupply

    modifier onlyGovernance() {
        require(
            msg.sender == governanceAddress,
            "Swapping: You are not authorized to perform this action"
        );
        _;
    }

    uint256 public TotalBurnedStates;
    uint256 public TotalTokensBurned;
    uint256 public totalBounty;
    uint256 private constant COOLDOWN_PERIOD = 24 hours;

    struct Vault {
        uint256 totalDeposited;
        uint256 totalAuctioned;
    }

    struct AuctionCycle {
        uint256 firstAuctionStart;
        bool isInitialized;
        uint256 auctionCount;
    }

    struct UserSwapInfo {
        bool hasSwapped;
        bool hasReverseSwap;
        uint256 cycle;
    }

    mapping(address => Vault) public vaults; // token => Vault
    mapping(address => mapping(address => bool)) public approvals; // user => spender => approved
    mapping(address => mapping(address => mapping(address => mapping(uint256 => UserSwapInfo))))
        public userSwapTotalInfo; // user => inputToken => stateToken => cycle => UserSwapInfo
    mapping(address => mapping(address => AuctionCycle)) public auctionCycles; // inputToken => stateToken => AuctionCycle
    mapping(address => uint256) public TotalStateBurnedByUser;
    mapping(address => uint256) private lastGovernanceUpdate;

    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address inputToken,
        address stateToken
    );
    event TokensDeposited(address indexed token, uint256 amount);
    event TokensSwapped(
        address indexed user,
        address indexed inputToken,
        address indexed stateToken,
        uint256 amountIn,
        uint256 amountOut
    );
    event TokenAdded(
        address indexed token,
        uint256 maxSupply,
        address pairAddress
    );

    constructor(address _gov) {
        governanceAddress = _gov;
    }

    function setTokenAddress(
        address state,
        address token
    ) external onlyGovernance {
        require(token != address(0), "Invalid token address");
        dav = IERC20(payable(token));
        stateToken = state;
    }

    function addToken(
        address token,
        uint256 maxSupply,
        address pairAddress
    ) external onlyGovernance {
        require(token != address(0), "Invalid token address");
        require(maxSupply > 0, "Invalid max supply");
        require(pairAddress != address(0), "Invalid pair address");
        require(!supportedTokens[token], "Token already added");

        supportedTokens[token] = true;
        maxSupplies[token] = maxSupply;
        pairAddresses[token] = pairAddress;

        // Schedule first auction at 18:30 IST (GMT+5:30)
        uint256 currentTime = block.timestamp;
        uint256 currentDayStart = (currentTime / 86400) * 86400; // Start of current day in UTC
        uint256 localDayStart = currentDayStart + TIMEZONE_OFFSET; // Adjust to IST (GMT+5:30)
        uint256 auctionStart = localDayStart + (7.5 * 3600); // Set to 18:30 IST (18.5 hours)

        // If current time is past 18:30 IST, schedule for next day
        if (currentTime >= auctionStart) {
            auctionStart += 86400; // Add 1 day
        }

        AuctionCycle storage cycle = auctionCycles[token][stateToken];
        cycle.firstAuctionStart = auctionStart;
        cycle.isInitialized = true;
        cycle.auctionCount = 0;

        auctionCycles[stateToken][token] = AuctionCycle({
            firstAuctionStart: auctionStart,
            isInitialized: true,
            auctionCount: 0
        });

        emit TokenAdded(token, maxSupply, pairAddress);
        emit AuctionStarted(
            auctionStart,
            auctionStart + AUCTION_DURATION,
            token,
            stateToken
        );
    }

    function getRatioPrice(address inputToken) public view returns (uint256) {
        require(supportedTokens[inputToken], "Unsupported token");
        IPair pair = IPair(pairAddresses[inputToken]);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(reserve0 > 0 && reserve1 > 0, "Invalid reserves");

        uint256 ratio;
        if (token0 == inputToken && token1 == stateToken) {
            ratio = (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else if (token0 == stateToken && token1 == inputToken) {
            ratio = (uint256(reserve0) * 1e18) / uint256(reserve1);
        } else {
            revert("Invalid pair");
        }

        return ratio;
    }

    function getNextAuctionStartTime(
        address inputToken
    ) public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized || cycle.auctionCount >= MAX_AUCTIONS) {
            return 0;
        }

        uint256 currentTime = block.timestamp;
        uint256 timeSinceFirst = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = timeSinceFirst / AUCTION_INTERVAL;

        // Calculate next auction start (every 50 days at 18:30 IST)
        uint256 nextCycleStart = cycle.firstAuctionStart +
            (currentCycle + 1) *
            AUCTION_INTERVAL;

        // Align to 18:30 IST
        uint256 dayStart = (nextCycleStart / 86400) * 86400; // Start of the day
        uint256 localDayStart = dayStart + TIMEZONE_OFFSET; // Adjust to IST (GMT+5:30)
        uint256 alignedStart = localDayStart + (18.5 * 3600); // Set to 18:30 IST

        // If alignedStart is in the past, move to next day
        if (alignedStart <= currentTime) {
            alignedStart += 86400;
        }

        return alignedStart;
    }

    function swapTokens(address user, address inputToken) public nonReentrant {
        require(supportedTokens[inputToken], "Unsupported token");
        require(stateToken != address(0), "State token cannot be null");
        require(
            dav.balanceOf(user) >= 1 * 10 ** 18,
            "Required enough DAV to participate"
        );

        uint256 currentAuctionCycle = getCurrentAuctionCycle(inputToken);
        AuctionCycle storage cycle = auctionCycles[inputToken][stateToken];
        require(cycle.auctionCount < MAX_AUCTIONS, "Maximum auctions reached");

        UserSwapInfo storage userSwapInfo = userSwapTotalInfo[user][inputToken][
            stateToken
        ][currentAuctionCycle];
        bool isReverseActive = isReverseAuctionActive(inputToken);

        if (isReverseActive) {
            require(isReverseActive, "No active reverse auction for this pair");
            require(
                !userSwapInfo.hasReverseSwap,
                "User already swapped in reverse auction for this cycle"
            );
        } else {
            require(
                isAuctionActive(inputToken),
                "No active auction for this pair"
            );
            require(
                !userSwapInfo.hasSwapped,
                "User already swapped in normal auction for this cycle"
            );
        }

        require(user != address(0), "Sender cannot be null");

        address tokenIn = isReverseActive ? stateToken : inputToken;
        address tokenOut = isReverseActive ? inputToken : stateToken;
        uint256 amountIn = calculateAuctionEligibleAmount(inputToken);
        uint256 amountOut = getOutPutAmount(inputToken);

        require(
            amountIn > 0,
            "Not enough balance in user wallet of input token"
        );
        require(amountOut > 0, "Output amount must be greater than zero");

        Vault storage vaultOut = vaults[tokenOut];
        require(
            vaultOut.totalDeposited >= vaultOut.totalAuctioned + amountOut,
            "Insufficient tokens in vault for the output token"
        );

        // Increment auction count if this is the first swap in a new cycle
        if (cycle.auctionCount < currentAuctionCycle) {
            cycle.auctionCount = currentAuctionCycle + 1;
            auctionCycles[stateToken][inputToken].auctionCount = cycle
                .auctionCount;
        }

        userSwapInfo.cycle = currentAuctionCycle;
        vaultOut.totalAuctioned += amountOut;

        if (isReverseActive) {
            userSwapInfo.hasReverseSwap = true;
            require(
                vaults[tokenOut].totalDeposited > 0,
                "Output token vault empty"
            );
            IERC20(tokenIn).safeTransferFrom(user, BURN_ADDRESS, amountIn);
            TotalBurnedStates += amountIn;
            TotalStateBurnedByUser[user] += amountIn;
            IERC20(tokenOut).safeTransfer(user, amountOut);
        } else {
            userSwapInfo.hasSwapped = true;
            require(
                vaults[tokenOut].totalDeposited > 0,
                "Output token vault empty"
            );
            IERC20(tokenIn).safeTransferFrom(user, BURN_ADDRESS, amountIn);
            TotalTokensBurned += amountIn;
            IERC20(tokenOut).safeTransfer(user, amountOut);
        }

        emit TokensSwapped(user, tokenIn, tokenOut, amountIn, amountOut);
    }

    function setInAmountPercentage(uint256 amount) public onlyGovernance {
        require(amount <= 100, "Percentage exceeds safe limit");
        percentage = amount;
    }

    function getUserHasSwapped(
        address user,
        address inputToken
    ) public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle(inputToken);
        return
            userSwapTotalInfo[user][inputToken][stateToken][getCycle]
                .hasSwapped;
    }

    function getUserHasReverseSwapped(
        address user,
        address inputToken
    ) public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle(inputToken);
        return
            userSwapTotalInfo[user][inputToken][stateToken][getCycle]
                .hasReverseSwap;
    }

    function isAuctionActive(address inputToken) public view returns (bool) {
        require(supportedTokens[inputToken], "Unsupported token");
        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized || cycle.auctionCount >= MAX_AUCTIONS) {
            return false;
        }

        uint256 currentTime = block.timestamp;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / AUCTION_INTERVAL;
        uint256 fullCycleLength = AUCTION_DURATION + AUCTION_INTERVAL;
        uint256 currentCyclePosition = timeSinceStart % fullCycleLength;

        if (
            currentCyclePosition < AUCTION_DURATION &&
            cycleNumber < MAX_AUCTIONS
        ) {
            return true;
        }

        return false;
    }

    function isReverseAuctionActive(
        address inputToken
    ) public view returns (bool) {
        require(supportedTokens[inputToken], "Unsupported token");
        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized || cycle.auctionCount >= MAX_AUCTIONS) {
            return false;
        }

        uint256 currentTime = block.timestamp;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / AUCTION_INTERVAL;

        // Reverse auction on 4th, 8th, 12th, etc. (every 4th auction)
        return
            (cycleNumber + 1) % 4 == 0 &&
            timeSinceStart % AUCTION_INTERVAL < REVERSE_DURATION;
    }

    function getCurrentAuctionCycle(
        address inputToken
    ) public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized || cycle.auctionCount >= MAX_AUCTIONS)
            return 0;

        uint256 timeSinceStart = block.timestamp - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / AUCTION_INTERVAL;

        return cycleNumber < MAX_AUCTIONS ? cycleNumber : MAX_AUCTIONS;
    }

    function calculateAuctionEligibleAmount(
        address inputToken
    ) public view returns (uint256) {
        require(supportedTokens[inputToken], "Unsupported token");
        uint256 currentCycle = getCurrentAuctionCycle(inputToken);
        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (
            currentCycle >= MAX_AUCTIONS || cycle.auctionCount >= MAX_AUCTIONS
        ) {
            return 0;
        }

        uint256 davbalance = dav.balanceOf(msg.sender);
        bool isReverse = isReverseAuctionActive(inputToken);
        if (davbalance == 0) {
            return 0;
        }

        uint256 firstCal = (maxSupplies[inputToken] * percentage) / 100 ether;
        uint256 secondCalWithDavMax = (firstCal / 5000000) * davbalance;
        uint256 baseAmount = isReverse
            ? secondCalWithDavMax * 2
            : secondCalWithDavMax;

        return baseAmount;
    }

    function getSwapAmounts(
        uint256 _amountIn,
        uint256 _amountOut
    ) public pure returns (uint256 newAmountIn, uint256 newAmountOut) {
        uint256 tempAmountOut = _amountIn;
        newAmountIn = _amountOut;
        newAmountOut = tempAmountOut;
        return (newAmountIn, newAmountOut);
    }

    function getOutPutAmount(address inputToken) public view returns (uint256) {
        require(supportedTokens[inputToken], "Unsupported token");
        uint256 currentRatio = getRatioPrice(inputToken);
        require(currentRatio > 0, "Invalid ratio");
        uint256 currentRatioNormalized = currentRatio / 1e18;

        uint256 userBalance = dav.balanceOf(msg.sender);
        if (userBalance == 0) {
            return 0;
        }

        bool isReverseActive = isReverseAuctionActive(inputToken);
        uint256 onePercent = calculateAuctionEligibleAmount(inputToken);
        require(onePercent > 0, "Invalid one percent balance");

        uint256 multiplications;
        if (isReverseActive) {
            multiplications = (onePercent * currentRatioNormalized) / 2;
        } else {
            multiplications = (onePercent * currentRatioNormalized);
            require(
                multiplications <= type(uint256).max / 2,
                "Multiplication overflow"
            );
            multiplications *= 2;
        }

        return multiplications;
    }

    function getTotalStateBurned() public view returns (uint256) {
        return TotalBurnedStates;
    }

    function getTotalStateBurnedByUser(
        address user
    ) public view returns (uint256) {
        return TotalStateBurnedByUser[user];
    }

    function getTotalBountyCollected() public view returns (uint256) {
        return totalBounty;
    }

    function getTotalTokensBurned() public view returns (uint256) {
        return TotalTokensBurned;
    }

    function getTimeLeftInAuction(
        address inputToken
    ) public view returns (uint256) {
        if (!isAuctionActive(inputToken)) {
            return 0;
        }

        AuctionCycle storage cycle = auctionCycles[inputToken][stateToken];
        uint256 currentTime = block.timestamp;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCyclePosition = timeSinceStart % AUCTION_INTERVAL;

        if (currentCyclePosition < AUCTION_DURATION) {
            return AUCTION_DURATION - currentCyclePosition;
        }

        return 0;
    }
}
