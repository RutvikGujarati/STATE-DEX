// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Decentralized_Autonomous_Vaults_DAV_V2_1 is
    ERC20,
    Ownable(msg.sender),
    ReentrancyGuard
{
    uint256 public constant MAX_SUPPLY = 5000000 ether; // 5 Million DAV Tokens
    uint256 public constant TOKEN_COST = 500000 ether;
    uint256 public constant REFERRAL_BONUS = 5; // 5% bonus for referrers
    uint256 public constant LIQUIDITY_SHARE = 20; // 20% LIQUIDITY SHARE
    uint256 public constant DEVELOPMENT_SHARE = 5; // 5% DEV SHARE
    uint256 public constant STATELP_SHARE = 60; // 5% DEV SHARE

    uint256 public mintedSupply; // Total Minted DAV Tokens
    /* liquidity and development wallets*/
    address public liquidityWallet;
    address public developmentWallet;
    address public StateLP;
    /* liquidity and development funds stroing*/
    uint256 public liquidityFunds;
    uint256 public developmentFunds;

    uint256 public deployTime;
    uint256 public constant davIncrement = 1;
    /* liquidity and development wallets withdrawal amount*/
    uint256 public totalLiquidityAllocated;
    uint256 public totalDevelopmentAllocated;
    //it is used in other token contracts
    uint256 public davHoldersCount;
    uint256 public totalRewardPerTokenStored;
    // follows for do not allow dav token transafers
    bool public transfersPaused = true;
    string public TransactionHash;
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
        uint256 amount
    );

    /* lastMingTimestamp will use in tokens for getting users mint time */
    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => bool) private isDAVHolder;
    mapping(address => uint256) public holderRewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userMintedAmount;

    mapping(address => address) public referrers; // Tracks who referred each user
    mapping(address => uint256) public referralRewards; // Tracks referral rewards earned

    constructor(
        address _liquidityWallet,
        address _developmentWallet,
        address _stateLP,
        string memory tokenName,
        string memory TokenSymbol
    ) ERC20(tokenName, TokenSymbol) {
        require(
            _liquidityWallet != address(0) && _developmentWallet != address(0),
            "Wallet addresses cannot be zero"
        );
        liquidityWallet = _liquidityWallet;
        developmentWallet = _developmentWallet;
        StateLP = _stateLP;
        _transferOwnership(msg.sender);
        deployTime = block.timestamp;
    }

    /**
	 @notice Transfer not allowing of Dav tokens logic
	* @dev Ensures that user can not transfer DAV tokens to other wallet or somewhere else.
	**/
    modifier whenTransfersAllowed() {
        require(!transfersPaused, "Transfers are currently paused");
        _;
    }

    //Transferring DAV tokens is not allowed after minting
    /**
     * @dev Prevent approvals to block indirect transfers via allowance
     */
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

    /**
     * @notice Allows users to mint DAV tokens by sending PLS.
     * @dev Ensures whole-number minting, checks supply limits, and distributes funds accordingly.
     * @param amount The number of DAV tokens to mint (must be in whole numbers of 1 DAV = 1 ether).
     */
    function mintDAV(
        uint256 amount,
        address referrer
    ) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(amount % 1 ether == 0, "Amount must be a whole number");
        require(mintedSupply + amount <= MAX_SUPPLY, "Max supply reached");

        uint256 cost = (amount * TOKEN_COST) / 1 ether;
        require(msg.value == cost, "Incorrect PLS amount sent");

        mintedSupply += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;

        uint256 holderShare = 0;
        if (davHoldersCount > 0 && totalSupply() > 0) {
            holderShare = (msg.value * 10) / 100;
            totalRewardPerTokenStored += (holderShare * 1e18) / totalSupply();
        }

        // Remove holderShare from remaining funds
        uint256 remainingFunds = msg.value - holderShare;

        // Breakdown of remaining 90% funds
        uint256 liquidityShare = (remainingFunds * LIQUIDITY_SHARE) / 100; // 20%
        uint256 developmentShare = (remainingFunds * DEVELOPMENT_SHARE) / 100; // 5%
        uint256 referralShare = 0;
        uint256 stateLPShare;

        // Handle referral bonus (5%)
        if (
            referrer != address(0) &&
            referrer != msg.sender &&
            referrers[msg.sender] == address(0)
        ) {
            referrers[msg.sender] = referrer;
            referralShare = (remainingFunds * REFERRAL_BONUS) / 100;

            referralRewards[referrer] += referralShare;

            (bool successRef, ) = referrer.call{value: referralShare}("");
            require(successRef, "Referral transfer failed");
            emit ReferralBonusPaid(referrer, msg.sender, referralShare);
        }

        // Remaining goes to State LP (60% if referral used, else 65%)
        uint256 distributedSoFar = liquidityShare +
            developmentShare +
            referralShare;
        stateLPShare = remainingFunds - distributedSoFar;

        require(
            liquidityShare +
                developmentShare +
                referralShare +
                stateLPShare +
                holderShare ==
                msg.value,
            "Distribution mismatch"
        );

        // Transfer to wallets
        (bool successLiquidity, ) = liquidityWallet.call{value: liquidityShare}(
            ""
        );
        require(successLiquidity, "Liquidity transfer failed");
        totalLiquidityAllocated += liquidityShare;
        emit FundsWithdrawn("Liquidity", liquidityShare, block.timestamp);

        (bool successDev, ) = developmentWallet.call{value: developmentShare}(
            ""
        );
        require(successDev, "Development transfer failed");
        totalDevelopmentAllocated += developmentShare;
        emit FundsWithdrawn("Development", developmentShare, block.timestamp);

        (bool successState, ) = StateLP.call{value: stateLPShare}("");
        require(successState, "State LP transfer failed");
        emit FundsWithdrawn("StateLP", stateLPShare, block.timestamp);

        // Update state
        userMintedAmount[msg.sender] += amount;
        if (!isDAVHolder[msg.sender]) {
            isDAVHolder[msg.sender] = true;
            davHoldersCount += 1;
            emit HolderAdded(msg.sender);
        }

        _updateRewards(msg.sender); // Before minting
        _mint(msg.sender, amount);
        _updateRewards(msg.sender); // After minting

        emit TokensMinted(msg.sender, amount, msg.value);
    }

    /**
     * @notice Allows users to claim their 10% of native currency (PLS).
     */
    function claimRewards() external nonReentrant {
        _updateRewards(msg.sender);
        uint256 reward = holderRewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        holderRewards[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");
        emit RewardsClaimed(msg.sender, reward);
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
        return (userBalance * 1e18) / totalSupply; // Return percentage as a scaled value (1e18 = 100%).
    }

    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }
}
