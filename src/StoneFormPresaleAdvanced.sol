// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface ISablierLockupLinear {
    struct Durations {
        uint40 cliff;
        uint40 total;
    }

    struct CreateWithDurations {
        address sender;
        address recipient;
        uint128 totalAmount;
        address asset;
        bool cancelable;
        bool transferable;
        Durations durations;
        uint128 startAmount;
        address broker;
    }

    function createWithDurations(
        CreateWithDurations calldata params
    ) external returns (uint256 streamId);
}

/*
 * @title STONEFORM TOKEN PRESALE CONTRACT (ADVANCED + SECURE)
 * @notice Tiered presale with Sablier vesting, secured with AccessControl, ReentrancyGuard, Pausable, and ECDSA signature verification
 */
contract StoneFormPresaleAdvanced is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /* ───────────── ROLES ───────────── */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /* ───────────── ERRORS ───────────── */
    error StoneFormPresale__InvalidTokenAddress();
    error StoneFormPresale__PresaleNotStarted();
    error StoneFormPresale__PresaleFinalized();
    error StoneFormPresale__HardCapReached();
    error StoneFormPresale__InvalidStartingTime();
    error StoneFormPresale__NoTierAdded();
    error StoneFormPresale__InvalidTierPrice();
    error StoneFormPresale__InvalidTierCaps();
    error StoneFormPresale__MismatchTokenAndSymbolArray();
    error StoneFormPresale__InvalidPurchaseAmount(string reason, uint256 amount, uint256 minMaxPurchase);
    error StoneFormPresale__InvalidPaymentToken();
    error StoneFormPresale__PresaleTokenNotSet();
    error StoneFormPresale__InsufficientPresaleTokenBalance();
    error StoneFormPresale__NotEnoughTokensPurchased();
    error StoneFormPresale__PresaleNotOpen();
    error StoneFormPresale__TGENotReached();
    error StoneFormPresale__PresaleNotFinalized();
    error StoneFormPresale__VestingAlreadyCreated();
    error StoneFormPresale__InvalidSignature();
    error StoneFormPresale__NonceAlreadyUsed();
    error StoneFormPresale__ZeroAddress();

    /* ───────────── ENUMS & STRUCTS ───────────── */
    enum Status {
        CLOSED,
        OPEN,
        FINALIZED
    }

    struct Tier {
        uint256 tierPrice;
        uint256 tierTotalTokenSold;
        uint256 maxCap;
        uint40 vestingDuration;
        uint256 tgeUnlockPercent;
    }

    struct Sign {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 nonce;
    }

    /* ───────────── STATE ───────────── */
    IERC20 public presaleToken;
    ISablierLockupLinear public sablier;

    address public pendingAdmin;

    Tier[] public tiers;
    mapping(string => address) public s_paymentTokens;
    uint256 public currentTier;

    uint256 public minPurchase;
    uint256 public maxPurchase;
    uint256 public hardCap;

    uint256 public startTime;
    uint256 public tgeTimestamp;

    uint256 public totalRaised;
    uint256 public totalTokenSold;

    Status public presaleStatus;

    mapping(address => uint256) public contributions;
    mapping(address => mapping(uint256 => uint256)) public userTierTokens;
    mapping(address => bool) public vestingCreated;
    mapping(uint256 => bool) public usedNonce;

    /* ───────────── EVENTS ───────────── */
    event TokensPurchased(address indexed buyer, uint256 collateralAmount, uint256 tokenAmount, uint256 tier);
    event TierChanged(uint256 newTier, uint256 newRate);
    event PresaleFinalized(uint256 tgeTimestamp);
    event VestingCreated(address indexed sender);
    event AdminTransferStarted(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferCompleted(address indexed newAdmin);
    event SignerUpdated(address indexed signer);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    /* ───────────── MODIFIERS ───────────── */
    modifier presaleActive() {
        if (presaleStatus != Status.OPEN) revert StoneFormPresale__PresaleNotOpen();
        if (block.timestamp < startTime) revert StoneFormPresale__PresaleNotStarted();
        if (totalTokenSold >= hardCap) revert StoneFormPresale__HardCapReached();
        _;
    }

    /* ───────────── CONSTRUCTOR ───────────── */
    constructor(
        address multisigAdmin,
        address signer,
        address _sablier,
        Tier[] memory _tiers,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) {
        if (multisigAdmin == address(0)) revert StoneFormPresale__ZeroAddress();
        if (signer == address(0)) revert StoneFormPresale__ZeroAddress();
        if (_sablier == address(0)) revert StoneFormPresale__ZeroAddress();
        if (_tiers.length == 0) revert StoneFormPresale__NoTierAdded();

        _grantRole(DEFAULT_ADMIN_ROLE, multisigAdmin);
        _grantRole(ADMIN_ROLE, multisigAdmin);
        _grantRole(SIGNER_ROLE, signer);

        sablier = ISablierLockupLinear(_sablier);
        presaleStatus = Status.CLOSED;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;

        for (uint256 i = 0; i < _tiers.length; i++) {
            if (_tiers[i].tierPrice == 0) revert StoneFormPresale__InvalidTierPrice();
            if (_tiers[i].maxCap == 0) revert StoneFormPresale__InvalidTierCaps();
            hardCap += _tiers[i].maxCap;
            tiers.push(_tiers[i]);
        }
    }

    /* ───────────── ADMIN SECURITY ───────────── */

    function initiateAdminTransfer(address newAdmin) external onlyRole(ADMIN_ROLE) {
        if (newAdmin == address(0)) revert StoneFormPresale__ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(msg.sender, newAdmin);
    }

    function acceptAdminRole() external {
        require(msg.sender == pendingAdmin, "Not pending admin");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        pendingAdmin = address(0);
        emit AdminTransferCompleted(msg.sender);
    }

    function updateSigner(address newSigner) external onlyRole(ADMIN_ROLE) {
        if (newSigner == address(0)) revert StoneFormPresale__ZeroAddress();
        _grantRole(SIGNER_ROLE, newSigner);
        emit SignerUpdated(newSigner);
    }

    /* ───────────── PAUSE CONTROL ───────────── */

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /* ───────────── CONFIGURATION ───────────── */

    function initPresale(uint256 _startTime) external onlyRole(ADMIN_ROLE) {
        if (_startTime < block.timestamp) revert StoneFormPresale__InvalidStartingTime();
        startTime = _startTime;
        presaleStatus = Status.OPEN;
    }

    function addNewPaymentToken(
        address[] memory _tokenAddresses,
        string[] memory _symbols
    ) external onlyRole(ADMIN_ROLE) {
        if (_tokenAddresses.length != _symbols.length) revert StoneFormPresale__MismatchTokenAndSymbolArray();
        for (uint256 i = 0; i < _symbols.length; i++) {
            s_paymentTokens[_symbols[i]] = _tokenAddresses[i];
        }
    }

    function setPresaleToken(address _token) external onlyRole(ADMIN_ROLE) {
        if (_token == address(0)) revert StoneFormPresale__InvalidTokenAddress();
        presaleToken = IERC20(_token);
    }

    function setStartTime(uint256 _newStartTime) external onlyRole(ADMIN_ROLE) {
        if (_newStartTime == 0) revert StoneFormPresale__InvalidStartingTime();
        startTime = _newStartTime;
    }

    function setMinMaxPurchase(uint256 _newValue, bool isMin) external onlyRole(ADMIN_ROLE) {
        if (isMin) {
            minPurchase = _newValue;
        } else {
            maxPurchase = _newValue;
        }
    }

    /* ───────────── PURCHASE LOGIC ───────────── */

    function purchaseTokens(
        uint256 _amount,
        string memory _paymentToken,
        Sign calldata sig
    ) external nonReentrant whenNotPaused presaleActive {
        // Verify signature
        if (usedNonce[sig.nonce]) revert StoneFormPresale__NonceAlreadyUsed();
        usedNonce[sig.nonce] = true;
        _verifySig(msg.sender, _amount, _paymentToken, sig);

        address paymentToken = s_paymentTokens[_paymentToken];
        if (paymentToken == address(0)) revert StoneFormPresale__InvalidPaymentToken();

        if (_amount < minPurchase) {
            revert StoneFormPresale__InvalidPurchaseAmount("amount inferior to min amount", _amount, minPurchase);
        }

        // Calculate how many tokens can be purchased with this amount
        uint256 remainingCollateral = _amount;
        uint256 totalTokensToGive = 0;
        uint256 totalCollateralUsed = 0;
        uint256 tierIndex = currentTier;

        while (remainingCollateral > 0 && tierIndex < tiers.length) {
            uint256 currentTierAvailable = tiers[tierIndex].maxCap - tiers[tierIndex].tierTotalTokenSold;

            if (currentTierAvailable == 0) {
                tierIndex++;
                if (tierIndex < tiers.length) {
                    currentTier = tierIndex;
                    emit TierChanged(tierIndex, tiers[tierIndex].tierPrice);
                }
                continue;
            }

            uint256 tokensFromCollateral = (remainingCollateral * 1e18) / tiers[tierIndex].tierPrice;

            uint256 tokensInThisTier = tokensFromCollateral > currentTierAvailable
                ? currentTierAvailable
                : tokensFromCollateral;

            uint256 collateralForThisTier = (tokensInThisTier * tiers[tierIndex].tierPrice) / 1e18;

            totalTokensToGive += tokensInThisTier;
            totalCollateralUsed += collateralForThisTier;
            remainingCollateral -= collateralForThisTier;

            tiers[tierIndex].tierTotalTokenSold += tokensInThisTier;
            userTierTokens[msg.sender][tierIndex] += tokensInThisTier;

            if (tokensInThisTier == currentTierAvailable && tierIndex < tiers.length - 1) {
                tierIndex++;
                currentTier = tierIndex;
                emit TierChanged(tierIndex, tiers[tierIndex].tierPrice);
            } else {
                break;
            }
        }

        if (totalTokensToGive == 0) revert StoneFormPresale__NotEnoughTokensPurchased();

        if (contributions[msg.sender] + totalCollateralUsed > maxPurchase) {
            revert StoneFormPresale__InvalidPurchaseAmount("Amount superior to maxPurchase", totalCollateralUsed, maxPurchase);
        }

        if (totalTokenSold + totalTokensToGive > hardCap) {
            revert StoneFormPresale__HardCapReached();
        }

        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), totalCollateralUsed);

        totalRaised += totalCollateralUsed;
        totalTokenSold += totalTokensToGive;
        contributions[msg.sender] += totalCollateralUsed;

        emit TokensPurchased(msg.sender, totalCollateralUsed, totalTokensToGive, tierIndex);
    }

    /* ───────────── FINALIZATION ───────────── */

    function finalizePresale(uint40 _tgeTimestamp) external onlyRole(ADMIN_ROLE) {
        if (presaleStatus == Status.FINALIZED) revert StoneFormPresale__PresaleFinalized();
        if (address(presaleToken) == address(0)) revert StoneFormPresale__PresaleTokenNotSet();
        if (presaleToken.balanceOf(address(this)) < totalTokenSold) revert StoneFormPresale__InsufficientPresaleTokenBalance();
        if (block.timestamp < _tgeTimestamp) revert StoneFormPresale__TGENotReached();

        presaleStatus = Status.FINALIZED;
        tgeTimestamp = _tgeTimestamp;

        presaleToken.approve(address(sablier), type(uint256).max);

        emit PresaleFinalized(_tgeTimestamp);
    }

    /* ───────────── VESTING ───────────── */

    function createMyVesting() external nonReentrant whenNotPaused {
        if (presaleStatus != Status.FINALIZED) revert StoneFormPresale__PresaleNotFinalized();
        if (vestingCreated[msg.sender]) revert StoneFormPresale__VestingAlreadyCreated();

        vestingCreated[msg.sender] = true;

        uint40 elapsedSinceTGE = uint40(block.timestamp - tgeTimestamp);

        for (uint256 i = 0; i < tiers.length; i++) {
            uint256 amount = userTierTokens[msg.sender][i];
            if (amount == 0) continue;

            Tier memory tier = tiers[i];

            uint40 elapsed = elapsedSinceTGE;
            if (elapsed > tier.vestingDuration) {
                elapsed = uint40(tier.vestingDuration);
            }

            uint256 tgeAmount = (amount * tier.tgeUnlockPercent) / 100;
            uint256 linearAmount = amount - tgeAmount;

            uint256 vestedLinear = tier.vestingDuration == 0
                ? linearAmount
                : (linearAmount * elapsed) / tier.vestingDuration;

            uint128 startAmount = uint128(tgeAmount + vestedLinear);
            uint40 remainingDuration = tier.vestingDuration - elapsed;

            sablier.createWithDurations(
                ISablierLockupLinear.CreateWithDurations({
                    sender: address(this),
                    recipient: msg.sender,
                    totalAmount: uint128(amount),
                    asset: address(presaleToken),
                    cancelable: false,
                    transferable: true,
                    broker: address(0),
                    startAmount: startAmount,
                    durations: ISablierLockupLinear.Durations({
                        cliff: 0,
                        total: remainingDuration
                    })
                })
            );
        }

        emit VestingCreated(msg.sender);
    }

    /* ───────────── INTERNAL ───────────── */

    function _verifySig(
        address caller,
        uint256 amount,
        string memory paymentToken,
        Sign calldata sig
    ) internal view {
        bytes32 hash = keccak256(
            abi.encodePacked(caller, amount, paymentToken, sig.nonce)
        );
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address recovered = ethSignedHash.recover(sig.v, sig.r, sig.s);

        if (!hasRole(SIGNER_ROLE, recovered)) revert StoneFormPresale__InvalidSignature();
    }

    /* ───────────── EMERGENCY ───────────── */

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        if (to == address(0)) revert StoneFormPresale__ZeroAddress();
        if (token == address(0)) {
            (bool success,) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit EmergencyWithdraw(token, amount);
    }

    receive() external payable {}
}
