// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Decentralized_Autonomous_Vaults_DAV_V2_1 is
    ERC20,
    Ownable(msg.sender),
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 5000000 ether; // 5 Million DAV Tokens
    uint256 public constant TOKEN_COST = 1000000 ether; // 500000 org
    uint256 public constant REFERRAL_BONUS = 5; // 5% bonus for referrers
    uint256 public constant LIQUIDITY_SHARE = 30; // 20% LIQUIDITY SHARE
    uint256 public constant DEVELOPMENT_SHARE = 5; // 5% DEV SHARE
    uint256 public constant HOLDER_SHARE = 10; // 10% HOLDER SHARE
    // Add this to track total distributed rewards for accounting
    uint256 public totalReferralRewardsDistributed;
    uint256 public unallocatedHolderDust; // Unused fractional dust from reward calc
    IERC20 public StateLP;
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
        uint256 amount;
        uint256 totalAtTime;
        uint256 timestamp;
        bool claimed;
    }

    mapping(address => uint256) public userBurnedAmount;

    mapping(address => UserBurn[]) public burnHistory;

    uint256 public totalStateBurned;
    mapping(address => BurnInfo) public userBurns;

    uint256 public mintedSupply; // Total Minted DAV Tokens
    address public liquidityWallet;
    address public developmentWallet;
    uint256 public liquidityFunds;
    address public stateToken;
    uint256 public developmentFunds;
    uint256 public stateLpTotalShare;
    uint256 public holderFunds; // Tracks ETH allocated for holder rewards

    uint256 public deployTime;
    uint256 public constant davIncrement = 1;
    uint256 public totalLiquidityAllocated;
    uint256 public totalDevelopmentAllocated;
    uint256 public davHoldersCount;
    uint256 public totalRewardPerTokenStored;
    bool public transfersPaused = true;
    string public TransactionHash;

    mapping(address => string) public userReferralCode; // User's own referral code
    mapping(string => address) public referralCodeToUser; // Referral code to user address
    mapping(address => string) public userToReferralCodeUsed; // Tracks which code a user used
    mapping(address => uint256) public referralRewards; // Tracks referral rewards earned

    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => bool) private isDAVHolder;
    mapping(address => uint256) public holderRewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userMintedAmount;
    mapping(address => uint256) public lastClaimedAt;

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
    event StuckETHWithdrawn(address indexed owner, uint256 amount);

    constructor(
        address _liquidityWallet,
        address _developmentWallet,
        address _stateToken,
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
        StateLP = IERC20(_stateToken);
        _transferOwnership(msg.sender);
        deployTime = block.timestamp;
    }

    modifier whenTransfersAllowed() {
        require(!transfersPaused, "Transfers are currently paused");
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
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override whenTransfersAllowed returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function viewLastMintTimeStamp(address user) public view returns (uint256) {
        return lastMintTimestamp[user];
    }

    function _updateRewards(address account) internal {
        if (account != address(0)) {
            holderRewards[account] = earned(account);
            userRewardPerTokenPaid[account] = totalRewardPerTokenStored;
        }
    }

    function earned(address account) public view returns (uint256) {
        return
            (balanceOf(account) *
                (totalRewardPerTokenStored - userRewardPerTokenPaid[account])) /
            1e18 +
            holderRewards[account];
    }

    function _generateReferralCode(
        address user
    ) internal view returns (string memory) {
        bytes32 hash = keccak256(
            abi.encodePacked(user, block.timestamp, block.number)
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
        holderShare = (value * HOLDER_SHARE) / 100;
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
        }

        if (davHoldersCount == 0 || totalSupply() == 0) {
            liquidityShare += holderShare;
            holderShare = 0;
        }

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

        // Distribute rewards to holders
        if (holderShare > 0 && totalSupply() > 0) {
            uint256 rewardPerToken = (holderShare * 1e18) / totalSupply();
            uint256 usedHolderShare = (rewardPerToken * totalSupply()) / 1e18;
            uint256 residualDust = holderShare - usedHolderShare;

            holderFunds += usedHolderShare;

            unallocatedHolderDust += residualDust;
            totalRewardPerTokenStored += rewardPerToken;
        }
        // Send referral bonus
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
        }

        // Transfer to liquidity wallet
        if (liquidityShare > 0) {
            (bool successLiquidity, ) = liquidityWallet.call{
                value: liquidityShare
            }("");
            require(successLiquidity, "Liquidity transfer failed");
            totalLiquidityAllocated += liquidityShare;
            emit FundsWithdrawn("Liquidity", liquidityShare, block.timestamp);
        }

        // Transfer to development wallet
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
        if (!isDAVHolder[msg.sender]) {
            isDAVHolder[msg.sender] = true;
            davHoldersCount += 1;
            emit HolderAdded(msg.sender);
        }

        _updateRewards(msg.sender);
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

    function isHolder(address account) external view returns (bool) {
        return isDAVHolder[account];
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

    function isValidReferralCode(
        string memory referralCode
    ) external view returns (bool) {
        return referralCodeToUser[referralCode] != address(0);
    }

    function getHolderFunds() external view returns (uint256) {
        return holderFunds;
    }

    // ------------------ StateLp functions ------------------------------
    function burnState(uint256 amount) external {
        require(balanceOf(msg.sender) >= MIN_DAV, "Need at least 10 DAV");
        require(amount > 0, "Burn amount must be > 0");
        require(
            StateLP.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        StateLP.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
        totalStateBurned += amount;
        userBurnedAmount[msg.sender] += amount;

        burnHistory[msg.sender].push(
            UserBurn({
                amount: amount,
                totalAtTime: totalStateBurned,
                timestamp: block.timestamp,
                claimed: false
            })
        );
    }

    function canClaim(address user) public view returns (bool) {
        UserBurn[] memory burns = burnHistory[user];
        if (burns.length == 0) return false;
        return block.timestamp >= lastClaimedAt[user] + 24 hours;
    }

    function getClaimablePLS(address user) public view returns (uint256) {
        UserBurn[] memory burns = burnHistory[user];
        if (burns.length == 0 || totalStateBurned == 0) return 0;

        uint256 userShare = (userBurnedAmount[user] * 1e18) / totalStateBurned;
        uint256 availablePLS = stateLpTotalShare / 12;
        uint256 totalReward = 0;

        for (uint256 i = 0; i < burns.length; i++) {
            if (!burns[i].claimed) {
                totalReward += (availablePLS * userShare) / 1e18;
            }
        }
        return totalReward;
    }

    function claimPLS() external {
        address user = msg.sender;
        require(canClaim(user), "Cannot claim yet");
        UserBurn[] storage burns = burnHistory[user];
        require(burns.length > 0, "No burns found");

        uint256 userShare = (userBurnedAmount[user] * 1e18) / totalStateBurned;
        uint256 availablePLS = stateLpTotalShare / 12;
        uint256 totalReward = 0;

        for (uint256 i = 0; i < burns.length; i++) {
            if (
                !burns[i].claimed &&
                block.timestamp >= burns[i].timestamp + 24 hours
            ) {
                totalReward += (availablePLS * userShare) / 1e18;
                burns[i].claimed = true;
            }
        }
        require(totalReward > 0, "Nothing to claim");

        lastClaimedAt[user] = block.timestamp;
        stateLpTotalShare -= totalReward;
        (bool success, ) = payable(user).call{value: totalReward}("");
        require(success, "PLS transfer failed");
    }

    function getContractPLSBalance() external view returns (uint256) {
        return stateLpTotalShare;
    }

    function getUserSharePercentage(
        address user
    ) external view returns (uint256) {
        if (totalStateBurned == 0) return 0;
        return (userBurnedAmount[user] * 100 * 1e18) / totalStateBurned / 1e18;
    }

    function getAllUsersBurnedPercentageSum() external view returns (uint256) {
        if (totalStateBurned == 0) return 0;
        return (totalStateBurned * 100 * 1e18) / totalStateBurned / 1e18;
    }
    receive() external payable {}
    fallback() external payable {}
}
