// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Decentralized_Autonomous_Vaults_DAV_V2_1} from "../MainTokens/DavToken.sol";

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}
contract UserToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 500000000000 ether; // 500 billion

    constructor(
        string memory name,
        string memory symbol,
        address _One,
        address _swap,
        address _owner
    ) ERC20(name, symbol) Ownable(_owner) {
        require(_One != address(0) && _swap != address(0), "Invalid address");

        uint256 onePercent = (MAX_SUPPLY * 1) / 100;
        uint256 ninetyNinePercent = MAX_SUPPLY - onePercent;

        _mint(_One, onePercent);
        _mint(_swap, ninetyNinePercent);
    }
}

contract Ratio_Swapping_Auctions_V2_1 is Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for IERC20;
    Decentralized_Autonomous_Vaults_DAV_V2_1 public dav;

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

    //For Airdrop
    uint256 private constant PRECISION = 1e18;
    uint256 public totalRewardDistributed;
    uint256 public totalAirdropMinted;
    uint256 public constant AUCTION_INTERVAL = 1 hours;
    uint256 public constant AUCTION_DURATION = 1 hours;
    uint256 public constant REVERSE_DURATION = 1 hours;
    uint256 public constant MAX_AUCTIONS = 20;
    uint256 public constant OWNER_REWARD_AMOUNT = 2500000 * 1e18;
    uint256 public constant CLAIM_INTERVAL = 1 hours;
    uint256 public constant MAX_SUPPLY = 500000000000 ether;
    uint256 public constant TIMEZONE_OFFSET = 19800; // GMT+5:30 in seconds (5.5 hours * 3600)
    uint256 public percentage = 1;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;
    uint256 public TotalBurnedStates;

    address public stateToken;
    address public governanceAddress;

    mapping(address => uint256) public userBaseReward;
    mapping(address => uint256) public lastDavMintTime;
    mapping(address => mapping(address => uint256)) public lastDavHolding; // user => token => last DAV holding
    mapping(address => mapping(address => uint256))
        public cumulativeDavHoldings;
    // Map user => array of deployed token names
    mapping(address => string[]) public userToTokenNames;

    // Map user + token name => token address
    mapping(address => mapping(string => address)) public deployedTokensByUser;

    mapping(address => address) public pairAddresses; // token => pair address
    mapping(address => bool) public supportedTokens; // token => isSupported
    mapping(address => address) public tokenOwners; // token => owner
    mapping(address => address[]) public ownerToTokens;
    mapping(string => bool) public isTokenNameUsed;

    mapping(address => mapping(address => uint256)) public lastClaimTime;
    mapping(string => string) public tokenNameToEmoji;

    event TokenDeployed(string name, address tokenAddress);

    mapping(address => mapping(address => bool)) public approvals; // user => spender => approved
    mapping(address => mapping(address => mapping(address => mapping(uint256 => UserSwapInfo))))
        public userSwapTotalInfo; // user => inputToken => stateToken => cycle => UserSwapInfo
    mapping(address => mapping(address => AuctionCycle)) public auctionCycles; // inputToken => stateToken => AuctionCycle
    mapping(address => uint256) public TotalStateBurnedByUser;
    mapping(address => uint256) public TotalTokensBurned;
    mapping(address => uint256) private lastGovernanceUpdate;
    mapping(address => mapping(address => bool)) public hasClaimed; // user => token => has claimed

    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address inputToken,
        address stateToken
    );
    event TokenDeployed(address tokenAddress);
    event TokensDeposited(address indexed token, uint256 amount);
    event RewardDistributed(address indexed user, uint256 amount);
    event TokensSwapped(
        address indexed user,
        address indexed inputToken,
        address indexed stateToken,
        uint256 amountIn,
        uint256 amountOut
    );
    event TokenAdded(address indexed token, address pairAddress);

    modifier onlyGovernance() {
        require(
            msg.sender == governanceAddress,
            "Swapping: You are not authorized to perform this action"
        );
        _;
    }
    constructor(address _gov) {
        governanceAddress = _gov;
    }

    // Deploy a Token
    function deployUserToken(
        string memory name,
        string memory symbol,
        string memory emojies,
        address _One,
        address _swap,
        address _owner
    ) external onlyGovernance returns (address) {
        require(!isTokenNameUsed[name], "Token name already used");
        require(
            deployedTokensByUser[msg.sender][name] == address(0),
            "Token address should not be zero"
        );

        UserToken token = new UserToken(name, symbol, _One, _swap, _owner);
        deployedTokensByUser[msg.sender][name] = address(token);
        userToTokenNames[msg.sender].push(name);
        isTokenNameUsed[name] = true;
        tokenNameToEmoji[name] = emojies;

        emit TokenDeployed(name, address(token));
        return address(token);
    }
    // Add and start Auction
    function addToken(
        address token,
        address pairAddress,
        address _tokenOwner,
        string memory _tokenName
    ) external onlyGovernance {
        require(token != address(0), "Invalid token address");
        require(pairAddress != address(0), "Invalid pair address");
        require(!supportedTokens[token], "Token already added");

        supportedTokens[token] = true;
        tokenOwners[token] = _tokenOwner;
        pairAddresses[token] = pairAddress;
        ownerToTokens[_tokenOwner].push(token);
        // Schedule first auction at 18:30 IST (GMT+5:30)
        uint256 auctionStart = block.timestamp;

        AuctionCycle storage cycle = auctionCycles[token][stateToken];
        cycle.firstAuctionStart = auctionStart;
        cycle.isInitialized = true;
        cycle.auctionCount = 0;

        auctionCycles[stateToken][token] = AuctionCycle({
            firstAuctionStart: auctionStart,
            isInitialized: true,
            auctionCount: 0
        });
        dav.updateTokenStatus(
            _tokenOwner,
            governanceAddress,
            _tokenName,
            Decentralized_Autonomous_Vaults_DAV_V2_1.TokenStatus.Processed
        );
        emit TokenAdded(token, pairAddress);
        emit AuctionStarted(
            auctionStart,
            auctionStart + AUCTION_DURATION,
            token,
            stateToken
        );
    }

    //used for only mainnet
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

    /**
     * @dev Distribute reward for a user's DAV holdings.
     */
    function distributeReward(
        address user,
        address inputToken
    ) external nonReentrant {
        // **Checks**
        require(user != address(0), "Invalid user address");
        require(supportedTokens[inputToken], "Unsupported token");
        require(msg.sender == user, "Invalid sender");

        uint256 currentDavHolding = dav.balanceOf(user);
        uint256 lastHolding = lastDavHolding[user][inputToken];
        uint256 newDavContributed = currentDavHolding > lastHolding
            ? currentDavHolding - lastHolding
            : 0;
        require(newDavContributed > 0, "No new DAV holdings for this token");

        // **Effects**
        uint256 reward = (newDavContributed * 10000 ether) / 1e18;

        cumulativeDavHoldings[user][inputToken] += newDavContributed;
        lastDavHolding[user][inputToken] = currentDavHolding;
        hasClaimed[user][inputToken] = true;

        // **Interactions**
        IERC20(inputToken).safeTransfer(msg.sender, reward);

        emit RewardDistributed(user, reward);
    }

    function giveRewardToTokenOwner(address token) public nonReentrant {
        // Check if the token has a registered owner
        address owner = tokenOwners[token];
        require(owner != address(0), "Token has no registered owner");

        // Determine claimant and reward amount
        address claimant;
        uint256 rewardAmount;

        if (msg.sender == governanceAddress) {
            claimant = governanceAddress;
            rewardAmount = 500000 * 1e18;
        } else {
            require(
                msg.sender == owner,
                "Only token owner or governance can claim"
            );
            require(
                dav.balanceOf(owner) >= 1e18,
                "Owner must hold at least 1 DAV"
            );
            claimant = owner;
            rewardAmount = 2500000 * 1e18;
        }

        // Enforce claim interval
        uint256 lastClaim = lastClaimTime[claimant][token];
        require(
            block.timestamp >= lastClaim + CLAIM_INTERVAL,
            "Claim not available yet"
        );

        // Update last claim time for the claimant
        lastClaimTime[claimant][token] = block.timestamp;

        // Transfer reward tokens to claimant
        require(
            IERC20(token).transfer(claimant, rewardAmount),
            "Reward transfer failed"
        );

        // Emit event for reward distribution
        emit RewardDistributed(claimant, rewardAmount);
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
        uint256 currentCycleNumber = getCurrentAuctionCycle(inputToken);
        require(currentCycleNumber < MAX_AUCTIONS, "Maximum auctions reached");

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
        uint256 TotalAmountIn = calculateAuctionEligibleAmount(inputToken);
        uint256 TotalAmountOut = getOutPutAmount(inputToken);

        uint256 amountIn = isReverseActive ? TotalAmountOut : TotalAmountIn;
        uint256 amountOut = isReverseActive ? TotalAmountIn : TotalAmountOut;
        require(
            amountIn > 0,
            "Not enough balance in user wallet of input token"
        );
        require(amountOut > 0, "Output amount must be greater than zero");

        require(
            IERC20(stateToken).balanceOf(address(this)) >= amountOut,
            "Insufficient tokens in vault for the output token"
        );

        // Increment auction count if this is the first swap in a new cycle
        if (cycle.auctionCount < currentAuctionCycle) {
            cycle.auctionCount = currentAuctionCycle + 1;
            auctionCycles[stateToken][inputToken].auctionCount = cycle
                .auctionCount;
        }

        userSwapInfo.cycle = currentAuctionCycle;

        if (isReverseActive) {
            userSwapInfo.hasReverseSwap = true;
            require(
                IERC20(tokenOut).balanceOf(address(this)) > 0,
                "Output token vault empty"
            );
            IERC20(tokenIn).safeTransferFrom(user, BURN_ADDRESS, amountIn);
            TotalBurnedStates += amountIn;
            TotalTokensBurned[tokenIn] += amountIn;
            TotalStateBurnedByUser[user] += amountIn;
            IERC20(tokenOut).safeTransfer(user, amountOut);
        } else {
            userSwapInfo.hasSwapped = true;
            require(
                IERC20(tokenOut).balanceOf(address(this)) > 0,
                "Output token vault empty"
            );
            IERC20(tokenIn).safeTransferFrom(user, BURN_ADDRESS, amountIn);
            TotalTokensBurned[tokenIn] += amountIn;
            IERC20(tokenOut).safeTransfer(user, amountOut);
        }

        emit TokensSwapped(user, tokenIn, tokenOut, amountIn, amountOut);
    }
    function setTokenAddress(
        address state,
        address _dav
    ) external onlyGovernance {
        require(_dav != address(0), "Invalid dav address");
        supportedTokens[state] = true;
        supportedTokens[_dav] = true;
        dav = Decentralized_Autonomous_Vaults_DAV_V2_1(payable(_dav));
        stateToken = state;
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
        if (!cycle.isInitialized) return false;

        uint256 fullCycleLength = AUCTION_DURATION + AUCTION_INTERVAL;
        uint256 currentTime = block.timestamp;

        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / fullCycleLength;
        if (cycleNumber >= MAX_AUCTIONS) return false;

        bool isFourthCycle = ((cycleNumber + 1) % 4 == 0);
        if (isFourthCycle) return false;

        uint256 currentCycleStart = cycle.firstAuctionStart +
            cycleNumber *
            fullCycleLength;
        uint256 auctionEndTime = currentCycleStart + AUCTION_DURATION;

        // Check if in active auction window (same for normal or reverse auction)
        return currentTime >= currentCycleStart && currentTime < auctionEndTime;
    }

    function isReverseAuctionActive(
        address inputToken
    ) public view returns (bool) {
        require(supportedTokens[inputToken], "Unsupported token");

        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized) return false;

        uint256 fullCycleLength = AUCTION_DURATION + AUCTION_INTERVAL;
        uint256 currentTime = block.timestamp;

        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / fullCycleLength;
        if (cycleNumber >= MAX_AUCTIONS) return false;

        uint256 currentCycleStart = cycle.firstAuctionStart +
            cycleNumber *
            fullCycleLength;
        uint256 auctionEndTime = currentCycleStart + AUCTION_DURATION;

        // Only on every 4th cycle (4,8,12...) we have reverse auction
        bool isFourthCycle = ((cycleNumber + 1) % 4 == 0);

        return
            isFourthCycle &&
            currentTime >= currentCycleStart &&
            currentTime < auctionEndTime;
    }

    function getCurrentAuctionCycle(
        address inputToken
    ) public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized) return 0;

        uint256 fullCycleLength = AUCTION_DURATION + AUCTION_INTERVAL;
        uint256 timeSinceStart = block.timestamp - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / fullCycleLength;

        // Cap it to MAX_AUCTIONS if needed
        if (cycleNumber >= MAX_AUCTIONS) {
            return MAX_AUCTIONS;
        }

        return cycleNumber;
    }

    function getAuctionTimeLeft(
        address inputToken
    ) public view returns (uint256) {
        require(supportedTokens[inputToken], "Unsupported token");

        AuctionCycle memory cycle = auctionCycles[inputToken][stateToken];
        if (!cycle.isInitialized) return 0;

        uint256 fullCycleLength = AUCTION_DURATION + AUCTION_INTERVAL;
        uint256 currentTime = block.timestamp;

        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 cycleNumber = timeSinceStart / fullCycleLength;
        if (cycleNumber >= MAX_AUCTIONS) return 0;

        uint256 currentCycleStart = cycle.firstAuctionStart +
            cycleNumber *
            fullCycleLength;
        uint256 auctionEndTime = currentCycleStart + AUCTION_DURATION;

        if (currentTime >= currentCycleStart && currentTime < auctionEndTime) {
            return auctionEndTime - currentTime;
        }

        return 0;
    }

    function calculateAuctionEligibleAmount(
        address inputToken
    ) public view returns (uint256) {
        require(supportedTokens[inputToken], "Unsupported token");

        uint256 currentCycle = getCurrentAuctionCycle(inputToken);
        if (currentCycle >= MAX_AUCTIONS) {
            return 0;
        }

        uint256 davbalance = dav.balanceOf(msg.sender);
        if (davbalance == 0) {
            return 0;
        }

        bool isReverse = isReverseAuctionActive(inputToken);

        // Adjust calculation to avoid truncation
        uint256 precisionFactor = 1e18; // Match typical ERC20 decimals
        uint256 firstCal = (MAX_SUPPLY * percentage * precisionFactor) / 100;
        uint256 secondCalWithDavMax = (firstCal / (5000000 * 1e18)) *
            davbalance;
        uint256 baseAmount = isReverse
            ? secondCalWithDavMax * 2
            : secondCalWithDavMax;

        return baseAmount / precisionFactor; // Scale back to correct units
    }

    function getOutPutAmount(address inputToken) public view returns (uint256) {
        require(supportedTokens[inputToken], "Unsupported token");
        uint256 currentRatio = 1000;
        require(currentRatio > 0, "Invalid ratio");
        uint256 currentRatioNormalized = 1000;

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

    //Airdrop getter functions
    function getClaimableReward(
        address user,
        address inputToken
    ) public view returns (uint256) {
        require(user != address(0), "Invalid user address");

        uint256 currentDavHolding = dav.balanceOf(user);
        uint256 lastHolding = lastDavHolding[user][inputToken];
        uint256 newDavContributed = currentDavHolding > lastHolding
            ? currentDavHolding - lastHolding
            : 0;

        // Calculate reward as in distributeReward
        uint256 reward = (newDavContributed * 10000 ether) / 1e18;

        return reward;
    }
    function getNextClaimTime(
        address token
    ) public view returns (uint256 timeLeftInSeconds) {
        address owner = tokenOwners[token];
        require(owner != address(0), "Token has no registered owner");

        address claimant = msg.sender == governanceAddress
            ? governanceAddress
            : owner;

        uint256 lastClaim = lastClaimTime[claimant][token];

        if (block.timestamp >= lastClaim + CLAIM_INTERVAL) {
            return 0;
        } else {
            return (lastClaim + CLAIM_INTERVAL) - block.timestamp;
        }
    }
    function hasAirdroppedClaim(
        address user,
        address inputToken
    ) public view returns (bool) {
        require(user != address(0), "Invalid user address");

        uint256 currentDavHolding = dav.balanceOf(user);
        uint256 lastHolding = lastDavHolding[user][inputToken];

        // If user has claimed and no new DAV is added, return true
        if (hasClaimed[user][inputToken] && currentDavHolding <= lastHolding) {
            return true;
        }

        // Otherwise, either they haven't claimed, or they have new DAV, so return false
        return false;
    }
    //burned getter
    function getTotalStateBurned() public view returns (uint256) {
        return TotalBurnedStates;
    }

    function getTotalStateBurnedByUser(
        address user
    ) public view returns (uint256) {
        return TotalStateBurnedByUser[user];
    }

    function getTotalTokensBurned(
        address inputToken
    ) public view returns (uint256) {
        return TotalTokensBurned[inputToken];
    }

    // Getter for deployed token by name
    function getUserTokenNames() external view returns (string[] memory) {
        return userToTokenNames[governanceAddress];
    }

    function getUserTokenAddress(
        string memory name
    ) external view returns (address) {
        return deployedTokensByUser[governanceAddress][name];
    }
    function getTokenOwner(address token) public view returns (address) {
        return tokenOwners[token];
    }
    function getTokensByOwner(
        address _owner
    ) public view returns (address[] memory) {
        return ownerToTokens[_owner];
    }

    function isTokenRenounced(
        address tokenAddress
    ) external view returns (bool) {
        return Ownable(tokenAddress).owner() == address(0);
    }

    function isTokenSupported(address token) public view returns (bool) {
        return supportedTokens[token];
    }
}
