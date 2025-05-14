// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Decentralized_Autonomous_Vaults_DAV_V2_1 is
    ERC20,
    Ownable(msg.sender),
    ReentrancyGuard // IERC20 initialization
{
    using SafeERC20 for IERC20;
    IERC20 public StateToken;
    //Global unit256 Variables
    // DAV TOken
    uint256 public constant MAX_SUPPLY = 10000000 ether; // 10 Million DAV Tokens
    uint256 public constant TOKEN_COST = 1000000 ether; // 1000000 org
    uint256 public constant REFERRAL_BONUS = 5; // 5% bonus for referrers
    uint256 public constant LIQUIDITY_SHARE = 30; // 20% LIQUIDITY SHARE
    uint256 public constant DEVELOPMENT_SHARE = 5; // 5% DEV SHARE
    uint256 public constant HOLDER_SHARE = 10; // 10% HOLDER SHARE
    uint256 private constant BASIS_POINTS = 10000;
    uint256 public totalReferralRewardsDistributed;
    uint256 public mintedSupply; // Total Minted DAV Tokens
    uint256 public stateLpTotalShare;
    uint256 public holderFunds; // Tracks ETH allocated for holder rewards
    uint256 public deployTime;
    uint256 public totalLiquidityAllocated;
    uint256 public totalDevelopmentAllocated;
    // @notice Tracks the number of DAV token holders
    // @dev Intentionally does not decrement davHoldersCount as token transfers are permanently paused for non-governance addresses, ensuring holders remain in the system
    uint256 public davHoldersCount;
    uint256 public totalRewardPerTokenStored;
    //State burn
    uint256 public totalStateBurned;
    uint256 public constant TREASURY_CLAIM_PERCENTAGE = 10; // 10% of treasury for claims
    uint256 public constant CLAIM_INTERVAL = 3 days; // 4 hour claim timer
    uint256 public constant MIN_DAV = 1 * 1e18;

    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;
    // @notice The governance address with special privileges, set at deployment
    // @dev Intentionally immutable to enforce a fixed governance structure; cannot be updated

    //Governance Privilage
    /*This implementation introduces a ratio-based liquidity provisioning (LP) mechanism, which is currently in beta and undergoing testing. The design is experimental and aims to collect meaningful data to inform and refine the concept. Due to its early-stage nature, certain centralized elements remain in place to ensure flexibility during the testing phase. These will be reviewed and potentially decentralized as the model matures.*/
    address public immutable governance;
    address public liquidityWallet;
    address public developmentWallet;
    address public stateToken;
    // @notice Transfers are permanently paused for non-governance addresses to enforce a no-transfer policy
    // @dev This is an intentional design choice to restrict token transfers and ensure the integrity of the airdrop mechanism.
    bool public transfersPaused = true;
    // @notice Mapping to track nonce for each user to ensure unique referral code generation
    // @dev Incremented each time a referral code is generated for a user
    mapping(address => uint256) private userNonce;
    struct UserBurn {
        uint256 amount;
        uint256 totalAtTime;
        uint256 timestamp;
        uint256 cycleNumber; // Tracks which 1-hour cycle this burn belongs to
        uint256 userShare; // User's share percentage at burn time (scaled by 1e18)
        bool claimed; // Tracks if this burn's reward has been claimed
    }
    enum TokenStatus {
        Pending,
        Processed
    }
    struct TokenEntry {
        address user;
        string tokenName;
        string emoji; // 🆕 Add this field
        TokenStatus status;
    }
    TokenEntry[] public allTokenEntries;
    mapping(address => uint256) public userBurnedAmount;
    mapping(address => mapping(uint256 => bool)) public hasClaimedCycle;
    mapping(address => UserBurn[]) public burnHistory;
    mapping(address => string) public userReferralCode; // User's own referral code
    mapping(string => address) public referralCodeToUser; // Referral code to user address
    mapping(address => uint256) public referralRewards; // Tracks referral rewards earned
    mapping(address => uint256) public lastMintTimestamp;
    // @notice Tracks whether an address is a DAV holder
    // @dev Set to true when a user mints tokens and never unset, as transfers are disabled, preventing users from exiting the holder system
    mapping(address => bool) private isDAVHolder;
    mapping(address => uint256) public holderRewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userMintedAmount;
    mapping(address => uint256) public lastBurnCycle;
    // Mapping to track allocated rewards per cycle per user
    mapping(address => mapping(uint256 => uint256)) public userCycleRewards;
    mapping(address => mapping(uint256 => bool)) public userBurnClaimed;
    mapping(address => mapping(uint256 => uint256)) public userCycleBurned; // Tracks user burns per cycle
    // Track allocated treasury per cycle (10% of treasury contributions)
    mapping(uint256 => uint256) public cycleTreasuryAllocation;
    // Track unclaimed PLS per cycle
    mapping(uint256 => uint256) public cycleUnclaimedPLS;
    mapping(uint256 => uint256) public cycleTotalBurned;
    mapping(address => string[]) public usersTokenNames;
    mapping(string => bool) public isTokenNameUsed;
    mapping(address => bytes32) public referralCommitments;
    event TokensBurned(address indexed user, uint256 amount, uint256 cycle);
    event RewardClaimed(address indexed user, uint256 amount, uint256 cycle);
    event TokensMinted(
        address indexed user,
        uint256 davAmount,
        uint256 stateAmount
    );
    event FundsWithdrawn(string fundType, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event HolderAdded(address indexed holder);
    event ReferralBonusPaid(
        address indexed referrer,
        address indexed referee,
        string referralCode,
        uint256 amount
    );
    event ReferralCodeGenerated(address indexed user, string referralCode);
    event TokenNameAdded(address indexed user, string name);
    event TokenStatusUpdated(
        address indexed owner,
        string tokenName,
        TokenStatus status
    );
    constructor(
        address _liquidityWallet,
        address _developmentWallet,
        address _stateToken,
        address _gov,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) {
        require(
            _liquidityWallet != address(0) &&
                _developmentWallet != address(0) &&
                _stateToken != address(0),
            "Wallet addresses cannot be zero"
        );
        liquidityWallet = _liquidityWallet;
        developmentWallet = _developmentWallet;
        stateToken = _stateToken;
        governance = _gov;
        _mint(_gov, 1000 ether);
        mintedSupply += 1000 ether;
        StateToken = IERC20(_stateToken);
        _transferOwnership(msg.sender);
        deployTime = block.timestamp;
    }
    modifier onlyGovernance() {
        require(msg.sender == governance, "Caller is not governance");
        _;
    }
    function updateLiquidityWallet(
        address _newLiquidityWallet
    ) external onlyGovernance {
        require(
            _newLiquidityWallet != address(0),
            "Liquidity wallet cannot be zero"
        );
        liquidityWallet = _newLiquidityWallet;
    }

    // Update function for developmentWallet
    function updateDevelopmentWallet(
        address _newDevelopmentWallet
    ) external onlyGovernance {
        require(
            _newDevelopmentWallet != address(0),
            "Development wallet cannot be zero"
        );
        developmentWallet = _newDevelopmentWallet;
    }
    // Restriction of transffering
    modifier whenTransfersAllowed() {
        require(
            !transfersPaused || msg.sender == governance,
            "Transfers are currently paused"
        );
        _;
    }
    function approve(
        address spender,
        uint256 amount
    ) public override whenTransfersAllowed returns (bool) {
        return super.approve(spender, amount);
    }
    function transfer(
        address recipient,
        uint256 amount
    ) public override whenTransfersAllowed returns (bool) {
        bool success = super.transfer(recipient, amount);
        if (success) {
            _assignReferralCodeIfNeeded(recipient); // safe, only if no code
        }
        return success;
    }
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override whenTransfersAllowed returns (bool) {
        bool success = super.transferFrom(sender, recipient, amount);
        if (success) {
            _assignReferralCodeIfNeeded(recipient); // safe, only if no code
        }
        return success;
    } // assign reffer to direct sended user
    function _assignReferralCodeIfNeeded(address user) internal {
        if (bytes(userReferralCode[user]).length == 0) {
            string memory code = _generateReferralCode(user);
            userReferralCode[user] = code;
            referralCodeToUser[code] = user;
            emit ReferralCodeGenerated(user, code);
        }
    }
    function _updateRewards(address account) internal {
        if (account != address(0) && account != governance) {
            holderRewards[account] = earned(account);
            userRewardPerTokenPaid[account] = totalRewardPerTokenStored;
        }
    }
    function earned(address account) public view returns (uint256) {
        if (account == governance) {
            return 0; // Governance address is excluded from earning rewards
        }
        return
            (balanceOf(account) *
                (totalRewardPerTokenStored - userRewardPerTokenPaid[account])) /
            1e18 +
            holderRewards[account];
    }

    /**
     * @notice Generates a unique referral code for a user
     * @dev Uses internal entropy sources and avoids miner-influenced values like blockhash
     * @param user The address of the user for whom the code is generated
     * @return A unique alphanumeric referral code
     */
    function _generateReferralCode(
        address user
    ) internal returns (string memory) {
        userNonce[user]++;

        // Avoid blockhash (miner-influenced); use timestamp and nonce for uniqueness
        bytes32 hash = keccak256(
            abi.encodePacked(
                user,
                userNonce[user],
                msg.sender,
                tx.origin,
                block.timestamp, // miner can control within a few seconds, but not enough to predict
                gasleft(), // adds minor entropy from tx conditions
                block.number // helps change across blocks
            )
        );

        return _toAlphanumericString(hash, 8);
    }

    function _toAlphanumericString(
        bytes32 hash,
        uint256 length
    ) internal pure returns (string memory) {
        bytes
            memory charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            // Use each byte in the hash to pick a character from the charset
            result[i] = charset[uint8(hash[i]) % charset.length];
        }
        return string(result);
    }
    function _calculateETHDistribution(
        uint256 value,
        address sender,
        string memory referralCode
    )
        internal
        view
        returns (
            uint256 holderShare,
            uint256 liquidityShare,
            uint256 developmentShare,
            uint256 referralShare,
            uint256 stateLPShare,
            address referrer
        )
    {
        // Explicitly exclude governance address from receiving holder share
        bool excludeHolderShare = sender == governance;
        require(
            !excludeHolderShare || sender != address(0),
            "Invalid governance address"
        );
        // Set holder share to 0 for governance address
        holderShare = excludeHolderShare ? 0 : (value * HOLDER_SHARE) / 100;
        liquidityShare = (value * LIQUIDITY_SHARE) / 100;
        developmentShare = (value * DEVELOPMENT_SHARE) / 100;
        referralShare = 0;
        referrer = address(0);
        if (bytes(referralCode).length > 0) {
            address _referrer = referralCodeToUser[referralCode];
            if (_referrer != address(0) && _referrer != sender) {
                referralShare = (value * REFERRAL_BONUS) / 100;
                referrer = _referrer;
            }
        } // If no holders or total supply is 0, redirect holder share to liquidity
        if (davHoldersCount == 0 || totalSupply() == 0) {
            liquidityShare += holderShare;
            holderShare = 0;
        } // Ensure total distribution does not exceed value
        uint256 distributed = holderShare +
            liquidityShare +
            developmentShare +
            referralShare;
        require(distributed <= value, "Over-allocation");
        stateLPShare = value - distributed;
    }

    function mintDAV(
        uint256 amount,
        string memory referralCode
    ) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(amount % 1 ether == 0, "Amount must be a whole number");
        require(mintedSupply + amount <= MAX_SUPPLY, "Max supply reached");
        uint256 cost = (amount * TOKEN_COST) / 1 ether;
        require(msg.value == cost, "Incorrect PLS amount sent");
        mintedSupply += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;
        if (bytes(userReferralCode[msg.sender]).length == 0) {
            string memory newReferralCode = _generateReferralCode(msg.sender);
            userReferralCode[msg.sender] = newReferralCode;
            referralCodeToUser[newReferralCode] = msg.sender;
            emit ReferralCodeGenerated(msg.sender, newReferralCode);
        }
        (
            uint256 holderShare,
            uint256 liquidityShare,
            uint256 developmentShare,
            uint256 referralShare,
            uint256 stateLPShare,
            address referrer
        ) = _calculateETHDistribution(msg.value, msg.sender, referralCode);
        stateLpTotalShare += stateLPShare;
        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        uint256 cycleAllocation = (stateLPShare * TREASURY_CLAIM_PERCENTAGE) /
            100;
        for (uint256 i = 0; i < 10; i++) {
            uint256 targetCycle = currentCycle + i;
            cycleTreasuryAllocation[targetCycle] += cycleAllocation;
            cycleUnclaimedPLS[targetCycle] += cycleAllocation;
        }
        // Distribute rewards to holders, excluding governance balance
        // @dev Total supply is never zero due to initial minting to governance during deployment, ensuring effectiveSupply calculations are safe
        if (holderShare > 0 && totalSupply() > balanceOf(governance)) {
            uint256 effectiveSupply = totalSupply() - balanceOf(governance);
            uint256 rewardPerToken = (holderShare * 1e18) / effectiveSupply;
            uint256 usedHolderShare = (rewardPerToken * effectiveSupply) / 1e18;

            holderFunds += usedHolderShare;
            totalRewardPerTokenStored += rewardPerToken;
        } // Send referral bonus
        if (referrer != address(0) && referralShare > 0) {
            referralRewards[referrer] += referralShare;
            totalReferralRewardsDistributed += referralShare;

            (bool successRef, ) = referrer.call{value: referralShare}("");
            require(successRef, "Referral transfer failed");

            emit ReferralBonusPaid(
                referrer,
                msg.sender,
                referralCode,
                referralShare
            );
        } // Transfer to liquidity wallet
        if (liquidityShare > 0) {
            (bool successLiquidity, ) = liquidityWallet.call{
                value: liquidityShare
            }("");
            require(successLiquidity, "Liquidity transfer failed");
            totalLiquidityAllocated += liquidityShare;
            emit FundsWithdrawn("Liquidity", liquidityShare, block.timestamp);
        } // Transfer to development wallet
        if (developmentShare > 0) {
            (bool successDev, ) = developmentWallet.call{
                value: developmentShare
            }("");
            require(successDev, "Development transfer failed");
            totalDevelopmentAllocated += developmentShare;
            emit FundsWithdrawn(
                "Development",
                developmentShare,
                block.timestamp
            );
        }
        userMintedAmount[msg.sender] += amount;
        // Only add non-governance addresses as holders
        if (!isDAVHolder[msg.sender] && msg.sender != governance) {
            isDAVHolder[msg.sender] = true;
            davHoldersCount += 1;
            emit HolderAdded(msg.sender);
        }
        _mint(msg.sender, amount);
        _updateRewards(msg.sender);
        emit TokensMinted(msg.sender, amount, msg.value);
    }
    function claimReward() external nonReentrant {
        require(balanceOf(msg.sender) > 0, "Not a DAV holder");

        _updateRewards(msg.sender);

        uint256 reward = holderRewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        holderRewards[msg.sender] = 0;
        holderFunds -= reward;

        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Reward transfer failed");
    }
    function getDAVHoldersCount() external view returns (uint256) {
        return davHoldersCount;
    }
    function getUserMintedAmount(address user) external view returns (uint256) {
        return userMintedAmount[user];
    }
    function getUserHoldingPercentage(
        address user
    ) public view returns (uint256) {
        uint256 userBalance = balanceOf(user);
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return 0;
        }
        return (userBalance * 1e18) / totalSupply;
    }
    function getUserReferralCode(
        address user
    ) external view returns (string memory) {
        return userReferralCode[user];
    }
    function viewLastMintTimeStamp(address user) public view returns (uint256) {
        return lastMintTimestamp[user];
    }
    // ------------------ Gettting Token data info functions ------------------------------
    function ProcessYourToken(
        string memory _tokenName,
        string memory _emoji
    ) public payable {
        require(bytes(_tokenName).length > 0, "Please provide tokenName");
        require(!isTokenNameUsed[_tokenName], "Token name already used");

        // ⚖️ Token entry limit is indirectly enforced via DAV balance
        // Each user is allowed to process one token per DAV they hold - so, no more unbound array
        uint256 userTokenBalance = balanceOf(msg.sender);
        uint256 tokensSubmitted = usersTokenNames[msg.sender].length;

        require(
            userTokenBalance > tokensSubmitted,
            "You need more DAV to process new token"
        );

        if (msg.sender != governance) {
            require(msg.value == 100000 ether, "Please give 100000 PLS");

            // Allocate all funds to State LP cycle like mintDAV
            uint256 stateLPShare = msg.value;
            uint256 currentCycle = (block.timestamp - deployTime) /
                CLAIM_INTERVAL;
            uint256 cycleAllocation = (stateLPShare *
                TREASURY_CLAIM_PERCENTAGE) / 100;

            for (uint256 i = 0; i < 10; i++) {
                uint256 targetCycle = currentCycle + i;
                cycleTreasuryAllocation[targetCycle] += cycleAllocation;
                cycleUnclaimedPLS[targetCycle] += cycleAllocation;
            }
        }

        usersTokenNames[msg.sender].push(_tokenName);
        allTokenEntries.push(
            TokenEntry(msg.sender, _tokenName, _emoji, TokenStatus.Pending)
        );
        isTokenNameUsed[_tokenName] = true;

        emit TokenNameAdded(msg.sender, _tokenName);
    }

    function getPendingTokenNames(
        address user
    ) public view returns (string[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < allTokenEntries.length; i++) {
            if (
                allTokenEntries[i].user == user &&
                allTokenEntries[i].status == TokenStatus.Pending
            ) {
                count++;
            }
        } // Create an array with the right size
        string[] memory pendingNames = new string[](count);
        uint256 index = 0;
        // Populate the result array
        for (uint256 i = 0; i < allTokenEntries.length; i++) {
            if (
                allTokenEntries[i].user == user &&
                allTokenEntries[i].status == TokenStatus.Pending
            ) {
                pendingNames[index] = allTokenEntries[i].tokenName;
                index++;
            }
        }
        return pendingNames;
    }

    /// @notice Updates the status of a user's submitted token name
    /// @dev This function can only be called by the governance address.
    /// Governance reviews and approves/rejects token submissions from users.
    /// This ensures centralized moderation over token listings to maintain integrity.
    /// While governance has authority, the process can be made transparent through on-chain within 24 hrs.
    function updateTokenStatus(
        address _owner,
        address _gov,
        string memory _tokenName,
        TokenStatus _status
    ) external {
        require(_gov == governance, "Only governance can update status");
        // Find and update the token entry
        for (uint256 i = 0; i < allTokenEntries.length; i++) {
            if (
                allTokenEntries[i].user == _owner &&
                keccak256(bytes(allTokenEntries[i].tokenName)) ==
                keccak256(bytes(_tokenName))
            ) {
                allTokenEntries[i].status = _status;
                emit TokenStatusUpdated(_owner, _tokenName, _status);
                break;
            }
        }
    }
    function getAllTokenEntries() public view returns (TokenEntry[] memory) {
        return allTokenEntries;
    }
    // ------------------ Burn functions ------------------------------
    //the treasury to reward Market Makers
    function burnState(uint256 amount) external {
        require(balanceOf(msg.sender) >= MIN_DAV, "Need at least 10 DAV");
        require(amount > 0, "Burn amount must be > 0");
        require(
            StateToken.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );
        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        // Check if user has unclaimed rewards from previous cycles
        require(
            !canClaim(msg.sender),
            "Must claim previous cycle rewards before burning"
        );
        // Update burn amounts
        totalStateBurned += amount;
        userBurnedAmount[msg.sender] += amount; // Track total burns by user
        userCycleBurned[msg.sender][currentCycle] += amount;

        cycleTotalBurned[currentCycle] += amount;
        // Calculate user share for this cycle
        uint256 userShare = cycleTotalBurned[currentCycle] > 0
            ? (userCycleBurned[msg.sender][currentCycle] * 1e18) /
                cycleTotalBurned[currentCycle]
            : 1e18; // 100% if first burner in cycle
        // Allocate reward for the current cycle
        uint256 cycleAllocation = cycleTreasuryAllocation[currentCycle];
        uint256 reward = (cycleAllocation * userShare) / (1e18);
        userCycleRewards[msg.sender][currentCycle] += reward;
        burnHistory[msg.sender].push(
            UserBurn({
                amount: amount,
                totalAtTime: cycleTotalBurned[currentCycle],
                timestamp: block.timestamp,
                cycleNumber: currentCycle,
                userShare: userShare,
                claimed: false
            })
        );
        lastBurnCycle[msg.sender] = currentCycle;
        StateToken.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
        emit TokensBurned(msg.sender, amount, currentCycle);
    }
    function canClaim(address user) public view returns (bool) {
        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        for (uint256 i = 0; i < currentCycle; i++) {
            if (cycleTreasuryAllocation[i] == 0) {
                continue;
            }
            if (userCycleRewards[user][i] > 0 && !hasClaimedCycle[user][i]) {
                return true; // User has claimable rewards in at least one past cycle
            }
        }
        return false;
    }
    function getClaimablePLS(address user) public view returns (uint256) {
        uint256 currentCycle = getCurrentCycle();
        uint256 totalClaimable = 0;

        for (uint256 i = 0; i <= currentCycle; i++) {
            if (cycleTreasuryAllocation[i] == 0 || hasClaimedCycle[user][i]) {
                continue;
            }

            uint256 userBurn = userCycleBurned[user][i];
            uint256 totalBurn = cycleTotalBurned[i];
            if (userBurn == 0 || totalBurn == 0) continue;

            uint256 userShare = (userBurn * 1e18) / totalBurn;
            uint256 cycleReward = (cycleTreasuryAllocation[i] * userShare) /
                1e18;

            uint256 availableFunds = cycleUnclaimedPLS[i];
            if (cycleReward > availableFunds) {
                cycleReward = availableFunds;
            }

            totalClaimable += cycleReward;
        }

        return totalClaimable;
    }

    function claimPLS() external {
        address user = msg.sender;
        require(canClaim(user), "No claimable rewards");

        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        require(currentCycle > 0, "Claim period not started");

        uint256 totalReward = 0;

        for (uint256 i = 0; i < currentCycle; i++) {
            if (cycleTreasuryAllocation[i] == 0 || hasClaimedCycle[user][i]) {
                continue;
            }

            uint256 userBurn = userCycleBurned[user][i];
            uint256 totalBurn = cycleTotalBurned[i];
            if (userBurn == 0 || totalBurn == 0) {
                continue; // Skip if user didn't burn or if no burns
            }
            uint256 reward = (cycleTreasuryAllocation[i] * userBurn) /
                totalBurn;

            require(cycleUnclaimedPLS[i] >= reward, "Insufficient cycle funds");
            cycleUnclaimedPLS[i] -= reward;

            if (reward > 0) {
                totalReward += reward;

                // Per-user reset
                hasClaimedCycle[user][i] = true;
                userBurnClaimed[user][i] = true;
                userCycleRewards[user][i] = 0;

                for (uint256 j = 0; j < burnHistory[user].length; j++) {
                    if (
                        burnHistory[user][j].cycleNumber == i &&
                        !burnHistory[user][j].claimed
                    ) {
                        burnHistory[user][j].claimed = true;
                    }
                }
            }
        }

        require(totalReward > 0, "Nothing to claim");
        require(
            (address(this).balance - holderFunds) >= totalReward,
            "Insufficient contract balance"
        );

        (bool success, ) = payable(user).call{value: totalReward}("");
        require(success, "PLS transfer failed");

        emit RewardClaimed(user, totalReward, currentCycle);
    }

    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - deployTime) / CLAIM_INTERVAL;
    }
    function getAvailableCycleFunds() public view returns (uint256) {
        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        require(currentCycle > 0, "No previous cycle exists");
        uint256 previousCycle = currentCycle - 1;
        uint256 unclaimed = cycleUnclaimedPLS[previousCycle];
        // Cross-check with cycleUnclaimedPLS to ensure correctness
        return
            unclaimed <= cycleUnclaimedPLS[previousCycle]
                ? unclaimed
                : cycleUnclaimedPLS[previousCycle];
    }
    function getTimeUntilNextClaim() public view returns (uint256) {
        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        uint256 nextClaimableAt = deployTime +
            (currentCycle + 1) *
            CLAIM_INTERVAL;
        return
            nextClaimableAt > block.timestamp
                ? nextClaimableAt - block.timestamp
                : 0;
    }
    function getContractPLSBalance() external view returns (uint256) {
        return address(this).balance - holderFunds;
    }
    function getUserSharePercentage(
        address user
    ) external view returns (uint256) {
        uint256 currentCycle = (block.timestamp - deployTime) / CLAIM_INTERVAL;
        // Check if current time is still inside this cycle
        if (
            block.timestamp < deployTime + (currentCycle + 1) * CLAIM_INTERVAL
        ) {
            // We're inside the current cycle – show live percentage
            uint256 userBurn = userCycleBurned[user][currentCycle];
            uint256 totalBurn = cycleTotalBurned[currentCycle];
            if (totalBurn == 0 || userBurn == 0) return 0;
            return (userBurn * BASIS_POINTS) / totalBurn; // basis points (10000 = 100.00%)
        } else {
            // Cycle has ended – show percentage from the previous cycle, if not yet claimed
            if (currentCycle == 0) return 0; // No previous cycle
            uint256 previousCycle = currentCycle - 1;
            if (
                userBurnClaimed[user][previousCycle] ||
                cycleTotalBurned[previousCycle] == 0
            ) {
                return 0;
            }
            uint256 userBurn = userCycleBurned[user][previousCycle];
            uint256 totalBurn = cycleTotalBurned[previousCycle];
            if (totalBurn == 0 || userBurn == 0) return 0;
            return (userBurn * BASIS_POINTS) / totalBurn;
        }
    }

    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }
    fallback() external payable {}
}
