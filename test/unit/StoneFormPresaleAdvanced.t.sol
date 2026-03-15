// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StoneFormPresaleAdvanced} from "../../src/StoneFormPresaleAdvanced.sol";
import {StoneFormToken, StoneFormMockUSD} from "../../src/StoneFormToken.sol";
import {MockSablier} from "../mocks/MockSablier.sol";

contract StoneFormPresaleAdvancedTest is Test {
    StoneFormPresaleAdvanced public presale;
    StoneFormToken public token;
    StoneFormMockUSD public mockUsd;
    MockSablier public mockSablier;

    address public admin = makeAddr("admin");
    uint256 public signerPrivateKey = 0xA11CE;
    address public signer;
    address public buyer = makeAddr("buyer");

    uint256 public constant MIN_PURCHASE = 1e18;
    uint256 public constant MAX_PURCHASE = 10_000_000 ether;
    uint256 public constant STARTING_BALANCE = 1_000_000 ether;

    event TokensPurchased(address indexed buyer, uint256 collateralAmount, uint256 tokenAmount, uint256 tier);
    event TierChanged(uint256 newTier, uint256 newRate);
    event PresaleFinalized(uint256 tgeTimestamp);
    event VestingCreated(address indexed sender);

    function setUp() external {
        signer = vm.addr(signerPrivateKey);

        // Deploy mocks
        mockSablier = new MockSablier();
        mockUsd = new StoneFormMockUSD(admin);

        // Build tiers
        StoneFormPresaleAdvanced.Tier[] memory tiers = _buildTiers();

        // Deploy presale
        presale = new StoneFormPresaleAdvanced(
            admin, signer, address(mockSablier), tiers, MIN_PURCHASE, MAX_PURCHASE
        );

        // Deploy token minted to presale
        token = new StoneFormToken(address(presale));

        // Admin setup
        vm.startPrank(admin);
        presale.setPresaleToken(address(token));

        address[] memory tokens = new address[](1);
        string[] memory symbols = new string[](1);
        tokens[0] = address(mockUsd);
        symbols[0] = "MUSD";
        presale.addNewPaymentToken(tokens, symbols);
        vm.stopPrank();

        // Fund buyer with MockUSD
        vm.prank(admin);
        mockUsd.transfer(buyer, STARTING_BALANCE);
    }

    function _buildTiers() internal pure returns (StoneFormPresaleAdvanced.Tier[] memory tiers) {
        tiers = new StoneFormPresaleAdvanced.Tier[](3);
        tiers[0] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 1e16,
            tierTotalTokenSold: 0,
            maxCap: 50_000 ether,
            vestingDuration: 180 days,
            tgeUnlockPercent: 10
        });
        tiers[1] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 15e15,
            tierTotalTokenSold: 0,
            maxCap: 30_000 ether,
            vestingDuration: 270 days,
            tgeUnlockPercent: 15
        });
        tiers[2] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 2e16,
            tierTotalTokenSold: 0,
            maxCap: 20_000 ether,
            vestingDuration: 365 days,
            tgeUnlockPercent: 20
        });
    }

    function _createSignature(
        address caller,
        uint256 amount,
        string memory paymentToken,
        uint256 nonce
    ) internal view returns (StoneFormPresaleAdvanced.Sign memory) {
        bytes32 hash = keccak256(abi.encodePacked(caller, amount, paymentToken, nonce));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedHash);
        return StoneFormPresaleAdvanced.Sign({v: v, r: r, s: s, nonce: nonce});
    }

    function _initPresale() internal {
        vm.prank(admin);
        presale.initPresale(block.timestamp + 1);
        vm.warp(block.timestamp + 2);
    }

    // ──────────────── Constructor Tests ────────────────

    function testConstructorSetsRoles() public view {
        assertTrue(presale.hasRole(presale.ADMIN_ROLE(), admin));
        assertTrue(presale.hasRole(presale.SIGNER_ROLE(), signer));
    }

    function testConstructorSetsTiers() public view {
        (uint256 price,,uint256 maxCap,,) = presale.tiers(0);
        assertEq(price, 1e16);
        assertEq(maxCap, 50_000 ether);
    }

    function testConstructorComputesHardCap() public view {
        assertEq(presale.hardCap(), 100_000 ether);
    }

    function testConstructorRevertsZeroAdmin() public {
        StoneFormPresaleAdvanced.Tier[] memory tiers = _buildTiers();
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__ZeroAddress.selector);
        new StoneFormPresaleAdvanced(address(0), signer, address(mockSablier), tiers, MIN_PURCHASE, MAX_PURCHASE);
    }

    function testConstructorRevertsZeroSigner() public {
        StoneFormPresaleAdvanced.Tier[] memory tiers = _buildTiers();
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__ZeroAddress.selector);
        new StoneFormPresaleAdvanced(admin, address(0), address(mockSablier), tiers, MIN_PURCHASE, MAX_PURCHASE);
    }

    function testConstructorRevertsNoTiers() public {
        StoneFormPresaleAdvanced.Tier[] memory tiers = new StoneFormPresaleAdvanced.Tier[](0);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__NoTierAdded.selector);
        new StoneFormPresaleAdvanced(admin, signer, address(mockSablier), tiers, MIN_PURCHASE, MAX_PURCHASE);
    }

    function testConstructorRevertsZeroTierPrice() public {
        StoneFormPresaleAdvanced.Tier[] memory tiers = new StoneFormPresaleAdvanced.Tier[](1);
        tiers[0] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 0, tierTotalTokenSold: 0, maxCap: 1000 ether, vestingDuration: 30 days, tgeUnlockPercent: 10
        });
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__InvalidTierPrice.selector);
        new StoneFormPresaleAdvanced(admin, signer, address(mockSablier), tiers, MIN_PURCHASE, MAX_PURCHASE);
    }

    // ──────────────── Init Presale Tests ────────────────

    function testInitPresale() public {
        uint256 startTime = block.timestamp + 100;
        vm.prank(admin);
        presale.initPresale(startTime);

        assertEq(presale.startTime(), startTime);
        assertEq(uint256(presale.presaleStatus()), uint256(StoneFormPresaleAdvanced.Status.OPEN));
    }

    function testInitPresaleRevertsNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        presale.initPresale(block.timestamp + 100);
    }

    function testInitPresaleRevertsPastTime() public {
        vm.prank(admin);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__InvalidStartingTime.selector);
        presale.initPresale(block.timestamp - 1);
    }

    // ──────────────── Purchase Tests ────────────────

    function testPurchaseTokens() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        assertGt(presale.totalTokenSold(), 0);
        assertGt(presale.totalRaised(), 0);
        assertGt(presale.contributions(buyer), 0);
    }

    function testPurchaseRevertsBeforeInit() public {
        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__PresaleNotOpen.selector);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();
    }

    function testPurchaseRevertsBelowMinPurchase() public {
        _initPresale();

        uint256 purchaseAmount = 0.1 ether; // below MIN_PURCHASE
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        vm.expectRevert();
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();
    }

    function testPurchaseRevertsInvalidPaymentToken() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "FAKE", 1);

        vm.startPrank(buyer);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__InvalidPaymentToken.selector);
        presale.purchaseTokens(purchaseAmount, "FAKE", sig);
        vm.stopPrank();
    }

    function testPurchaseRevertsReusedNonce() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount * 2);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);

        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__NonceAlreadyUsed.selector);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();
    }

    function testPurchaseRevertsInvalidSignature() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        // Sign with wrong key
        uint256 wrongKey = 0xBEEF;
        bytes32 hash = keccak256(abi.encodePacked(buyer, purchaseAmount, "MUSD", uint256(1)));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedHash);
        StoneFormPresaleAdvanced.Sign memory sig = StoneFormPresaleAdvanced.Sign({v: v, r: r, s: s, nonce: 1});

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__InvalidSignature.selector);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();
    }

    function testPurchaseProgressesThroughTiers() public {
        _initPresale();

        // Buy enough to fill tier 0 (50_000 tokens at 0.01 price = 500 collateral)
        uint256 purchaseAmount = 500 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        assertEq(presale.totalTokenSold(), 50_000 ether);
        assertEq(presale.currentTier(), 1);
    }

    // ──────────────── Pause Tests ────────────────

    function testPauseBlocksPurchase() public {
        _initPresale();

        vm.prank(admin);
        presale.pause();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        vm.expectRevert();
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();
    }

    function testUnpauseAllowsPurchase() public {
        _initPresale();

        vm.prank(admin);
        presale.pause();

        vm.prank(admin);
        presale.unpause();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);

        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        assertGt(presale.totalTokenSold(), 0);
    }

    // ──────────────── Finalize Tests ────────────────

    function testFinalizePresale() public {
        _initPresale();

        // Make a purchase first
        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);
        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        uint40 tgeTimestamp = uint40(block.timestamp);

        vm.prank(admin);
        presale.finalizePresale(tgeTimestamp);

        assertEq(uint256(presale.presaleStatus()), uint256(StoneFormPresaleAdvanced.Status.FINALIZED));
    }

    function testFinalizeRevertsWithoutPresaleToken() public {
        // Deploy new presale without setting presale token
        StoneFormPresaleAdvanced.Tier[] memory tiers = _buildTiers();
        StoneFormPresaleAdvanced freshPresale = new StoneFormPresaleAdvanced(
            admin, signer, address(mockSablier), tiers, MIN_PURCHASE, MAX_PURCHASE
        );

        vm.prank(admin);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__PresaleTokenNotSet.selector);
        freshPresale.finalizePresale(uint40(block.timestamp));
    }

    function testFinalizeRevertsDoubleFinalize() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);
        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        vm.prank(admin);
        presale.finalizePresale(uint40(block.timestamp));

        vm.prank(admin);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__PresaleFinalized.selector);
        presale.finalizePresale(uint40(block.timestamp));
    }

    // ──────────────── Vesting Tests ────────────────

    function testCreateMyVesting() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);
        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        vm.prank(admin);
        presale.finalizePresale(uint40(block.timestamp));

        vm.prank(buyer);
        presale.createMyVesting();

        assertTrue(presale.vestingCreated(buyer));
    }

    function testCreateVestingRevertsBeforeFinalize() public {
        _initPresale();

        vm.prank(buyer);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__PresaleNotFinalized.selector);
        presale.createMyVesting();
    }

    function testCreateVestingRevertsDoubleCreation() public {
        _initPresale();

        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);
        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        vm.prank(admin);
        presale.finalizePresale(uint40(block.timestamp));

        vm.prank(buyer);
        presale.createMyVesting();

        vm.prank(buyer);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__VestingAlreadyCreated.selector);
        presale.createMyVesting();
    }

    // ──────────────── Admin Security Tests ────────────────

    function testTwoStepAdminTransfer() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        presale.initiateAdminTransfer(newAdmin);

        assertEq(presale.pendingAdmin(), newAdmin);

        vm.prank(newAdmin);
        presale.acceptAdminRole();

        assertTrue(presale.hasRole(presale.ADMIN_ROLE(), newAdmin));
        assertEq(presale.pendingAdmin(), address(0));
    }

    function testAcceptAdminRevertsWrongCaller() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        presale.initiateAdminTransfer(newAdmin);

        vm.prank(buyer);
        vm.expectRevert("Not pending admin");
        presale.acceptAdminRole();
    }

    function testUpdateSigner() public {
        address newSigner = makeAddr("newSigner");

        vm.prank(admin);
        presale.updateSigner(newSigner);

        assertTrue(presale.hasRole(presale.SIGNER_ROLE(), newSigner));
    }

    // ──────────────── Emergency Withdraw Tests ────────────────

    function testEmergencyWithdrawERC20() public {
        _initPresale();

        // Purchase so presale has mockUSD
        uint256 purchaseAmount = 100 ether;
        StoneFormPresaleAdvanced.Sign memory sig = _createSignature(buyer, purchaseAmount, "MUSD", 1);
        vm.startPrank(buyer);
        mockUsd.approve(address(presale), purchaseAmount);
        presale.purchaseTokens(purchaseAmount, "MUSD", sig);
        vm.stopPrank();

        uint256 presaleBalance = mockUsd.balanceOf(address(presale));
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        presale.emergencyWithdraw(address(mockUsd), recipient, presaleBalance);

        assertEq(mockUsd.balanceOf(recipient), presaleBalance);
    }

    function testEmergencyWithdrawRevertsNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        presale.emergencyWithdraw(address(mockUsd), buyer, 100 ether);
    }

    function testEmergencyWithdrawRevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__ZeroAddress.selector);
        presale.emergencyWithdraw(address(mockUsd), address(0), 100 ether);
    }

    // ──────────────── Config Setter Tests ────────────────

    function testSetPresaleToken() public {
        address newToken = makeAddr("newToken");
        vm.prank(admin);
        presale.setPresaleToken(newToken);
        assertEq(address(presale.presaleToken()), newToken);
    }

    function testSetPresaleTokenRevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(StoneFormPresaleAdvanced.StoneFormPresale__InvalidTokenAddress.selector);
        presale.setPresaleToken(address(0));
    }

    function testSetMinPurchase() public {
        vm.prank(admin);
        presale.setMinMaxPurchase(5 ether, true);
        assertEq(presale.minPurchase(), 5 ether);
    }

    function testSetMaxPurchase() public {
        vm.prank(admin);
        presale.setMinMaxPurchase(5_000_000 ether, false);
        assertEq(presale.maxPurchase(), 5_000_000 ether);
    }
}
