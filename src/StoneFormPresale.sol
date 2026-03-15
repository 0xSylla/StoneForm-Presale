// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title StoneForm ICO V2 (Secure)
contract StoneForm_ICO_V2 is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /* ───────────── ROLES ───────────── */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE"); // MULTISIG
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE"); // BACKEND

    /* ───────────── STATE ───────────── */
    IERC20 public saleToken;
    uint256 public tokenPerUSD; // 18 decimals

    address public pendingAdmin; // for 2-step ownership

    mapping(uint256 => bool) public usedNonce;

    struct TokenDetail {
        string name;
        address oracle;
        address token;
        uint256 decimals;
        bool enabled;
    }

    mapping(uint256 => TokenDetail) public paymentTokens;

    /* ───────────── EVENTS ───────────── */
    event TokensPurchased(address indexed buyer, address indexed recipient, uint256 amount);
    event TokenPerUSDUpdated(uint256 newPrice);
    event PaymentTokenUpdated(uint256 indexed id);
    event SaleTokenUpdated(address token);
    event AdminTransferStarted(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferCompleted(address indexed newAdmin);
    event SignerUpdated(address indexed signer);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    /* ───────────── CONSTRUCTOR ───────────── */
    constructor(address multisigAdmin, address signer, IERC20 _saleToken, uint256 _tokenPerUSD) {
        require(multisigAdmin != address(0), "Invalid admin");
        require(signer != address(0), "Invalid signer");

        _grantRole(DEFAULT_ADMIN_ROLE, multisigAdmin);
        _grantRole(ADMIN_ROLE, multisigAdmin);
        _grantRole(SIGNER_ROLE, signer);

        saleToken = _saleToken;
        tokenPerUSD = _tokenPerUSD;
    }

    /* ───────────── ADMIN SECURITY ───────────── */

    /// 2-step admin rotation (SAFE)
    function initiateAdminTransfer(address newAdmin) external onlyRole(ADMIN_ROLE) {
        require(newAdmin != address(0), "Zero address");
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
        require(newSigner != address(0), "Zero address");
        _grantRole(SIGNER_ROLE, newSigner);
        emit SignerUpdated(newSigner);
    }

    /* ───────────── CONFIGURATION ───────────── */

    function setPaymentToken(
        uint256 id,
        string calldata name,
        address oracle,
        address token,
        uint256 decimals,
        bool enabled
    ) external onlyRole(ADMIN_ROLE) {
        require(oracle != address(0), "Invalid oracle");
        paymentTokens[id] = TokenDetail(name, oracle, token, decimals, enabled);
        emit PaymentTokenUpdated(id);
    }

    function updateTokenPerUSD(uint256 newPrice) external onlyRole(ADMIN_ROLE) {
        tokenPerUSD = newPrice;
        emit TokenPerUSDUpdated(newPrice);
    }

    function updateSaleToken(address newSaleToken) external onlyRole(ADMIN_ROLE) {
        require(newSaleToken != address(0), "Zero address");
        saleToken = IERC20(newSaleToken);
        emit SaleTokenUpdated(newSaleToken);
    }

    /* ───────────── PAUSE CONTROL ───────────── */

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /* ───────────── BUY LOGIC ───────────── */

    struct Sign {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 nonce;
    }

    function buy(address recipient, uint256 paymentType, uint256 amountPaid, Sign calldata sig)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(!usedNonce[sig.nonce], "Nonce used");
        usedNonce[sig.nonce] = true;

        TokenDetail memory t = paymentTokens[paymentType];
        require(t.enabled, "Payment disabled");

        _verifySig(paymentType, recipient, msg.sender, amountPaid, sig);

        uint256 tokenAmount = _calculateTokens(paymentType, amountPaid);

        if (t.token == address(0)) {
            require(msg.value == amountPaid, "Invalid BNB");
        } else {
            IERC20(t.token).safeTransferFrom(msg.sender, address(this), amountPaid);
        }

        saleToken.safeTransfer(recipient, tokenAmount);
        emit TokensPurchased(msg.sender, recipient, tokenAmount);
    }

    /* ───────────── INTERNAL ───────────── */

    function _calculateTokens(uint256 id, uint256 paid) internal view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(paymentTokens[id].oracle).latestRoundData();

        // Chainlink price is usually 8 decimals. tokenPerUSD is 18 decimals.
        // paid is in token decimals.
        uint256 usdValue = (uint256(price) * tokenPerUSD) / 1e8;
        return (usdValue * paid) / (10 ** paymentTokens[id].decimals);
    }

    function _verifySig(uint256 asset, address recipient, address caller, uint256 amount, Sign calldata sig)
        internal
        view
    {
        bytes32 hash = keccak256(abi.encodePacked(asset, recipient, caller, amount, sig.nonce));

        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address recovered = ethSignedHash.recover(sig.v, sig.r, sig.s);

        require(hasRole(SIGNER_ROLE, recovered), "Invalid signer");
    }

    /* ───────────── EMERGENCY ───────────── */

    function emergencyWithdraw(address token, address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "Zero address");
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit EmergencyWithdraw(token, amount);
    }
}
