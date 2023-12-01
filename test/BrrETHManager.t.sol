// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC4626} from "solady/tokens/ERC4626.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Helper} from "test/Helper.sol";
import {BrrETH} from "src/BrrETH.sol";
import {BrrETHManager} from "src/BrrETHManager.sol";

contract BrrETHManagerTest is Helper {
    using SafeTransferLib for address;

    BrrETH public immutable vault = new BrrETH(address(this));
    BrrETHManager public immutable manager = new BrrETHManager(address(vault));

    constructor() {
        _WETH.safeApproveWithRetry(address(manager), type(uint256).max);
        address(vault).safeApproveWithRetry(
            address(manager),
            type(uint256).max
        );
    }

    function _getAssets(uint256 assets) private pure returns (uint256) {
        return (assets * 9_999) / 10_000;
    }

    /*//////////////////////////////////////////////////////////////
                             constructor
    //////////////////////////////////////////////////////////////*/

    function testConstructor() external {
        assertEq(address(vault), address(manager.brrETH()));
        assertEq(
            type(uint256).max,
            ERC20(_WETH).allowance(address(manager), _COMET)
        );
        assertEq(
            type(uint256).max,
            ERC20(_COMET).allowance(address(manager), address(vault))
        );
    }

    /*//////////////////////////////////////////////////////////////
                             approveTokens
    //////////////////////////////////////////////////////////////*/

    function testApproveTokens() external {
        vm.startPrank(address(manager));

        _WETH.safeApprove(_COMET, 0);
        _COMET.safeApprove(address(vault), 0);

        vm.stopPrank();

        assertEq(0, ERC20(_WETH).allowance(address(manager), _COMET));
        assertEq(0, ERC20(_COMET).allowance(address(manager), address(vault)));

        manager.approveTokens();

        assertEq(
            type(uint256).max,
            ERC20(_WETH).allowance(address(manager), _COMET)
        );
        assertEq(
            type(uint256).max,
            ERC20(_COMET).allowance(address(manager), address(vault))
        );
    }

    /*//////////////////////////////////////////////////////////////
                             deposit (ETH)
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositETHInvalidAmount() external {
        uint256 amount = 0;
        address to = address(this);

        vm.expectRevert(BrrETHManager.InvalidAmount.selector);

        manager.deposit{value: amount}(to);
    }

    function testCannotDepositETHInvalidAddress() external {
        uint256 amount = 1;
        address to = address(0);

        vm.expectRevert(BrrETHManager.InvalidAddress.selector);

        manager.deposit{value: amount}(to);
    }

    function testDepositETH() external {
        address msgSender = address(this);
        uint256 msgValue = 1 ether;
        address to = address(this);

        // State before calling `deposit`.
        uint256 msgSenderEthBalance = msgSender.balance;
        uint256 toVaultBalance = vault.balanceOf(to);
        uint256 cometWethBalance = _WETH.balanceOf(_COMET);
        uint256 vaultCometBalance = _COMET.balanceOf(address(vault));
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 vaultTotalSupply = vault.totalAssets();

        // Values with various factors taken into account.
        uint256 depositedAssets = msgValue - 1;
        uint256 sharesPreview = vault.previewDeposit(depositedAssets);
        uint256 postDepositAssets = depositedAssets - 1;

        vm.prank(msgSender);
        vm.expectEmit(true, true, true, true, address(vault));

        emit ERC4626.Deposit(
            address(manager),
            to,
            depositedAssets,
            sharesPreview
        );

        uint256 shares = manager.deposit{value: msgValue}(to);

        assertEq(sharesPreview, shares);
        assertEq(msgSenderEthBalance - msgValue, msgSender.balance);
        assertEq(toVaultBalance + shares, vault.balanceOf(to));
        assertEq(cometWethBalance + msgValue, _WETH.balanceOf(_COMET));
        assertEq(
            vaultCometBalance + postDepositAssets,
            _COMET.balanceOf(address(vault))
        );
        assertEq(vaultTotalAssets + postDepositAssets, vault.totalAssets());
        assertEq(vaultTotalSupply + shares, vault.totalSupply());
    }

    function testDepositETHFuzz(
        address msgSender,
        uint80 msgValue,
        address to
    ) external {
        vm.assume(msgSender != address(0) && to != address(0));
        vm.assume(msgValue > _MIN_DEPOSIT);
        vm.deal(msgSender, msgValue);

        // State before calling `deposit`.
        uint256 msgSenderEthBalance = msgSender.balance;
        uint256 toVaultBalance = vault.balanceOf(to);
        uint256 cometWethBalance = _WETH.balanceOf(_COMET);
        uint256 vaultCometBalance = _COMET.balanceOf(address(vault));
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 vaultTotalSupply = vault.totalAssets();

        // Values with various factors taken into account.
        uint256 depositedAssets = msgValue - 1;
        uint256 sharesPreview = vault.previewDeposit(depositedAssets);
        uint256 postDepositAssets = depositedAssets - 1;

        vm.prank(msgSender);
        vm.expectEmit(true, true, true, false, address(vault));

        emit ERC4626.Deposit(
            address(manager),
            to,
            depositedAssets,
            sharesPreview
        );

        uint256 shares = manager.deposit{value: msgValue}(to);

        assertEq(sharesPreview, shares);
        assertEq(msgSenderEthBalance - msgValue, msgSender.balance);
        assertEq(toVaultBalance + shares, vault.balanceOf(to));
        assertEq(cometWethBalance + msgValue, _WETH.balanceOf(_COMET));
        assertEq(
            vaultCometBalance + postDepositAssets,
            _COMET.balanceOf(address(vault))
        );
        assertEq(vaultTotalAssets + postDepositAssets, vault.totalAssets());
        assertEq(vaultTotalSupply + shares, vault.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                             deposit (WETH)
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositWETHInvalidAmount() external {
        uint256 amount = 0;
        address to = address(this);

        vm.expectRevert(BrrETHManager.InvalidAmount.selector);

        manager.deposit(amount, to);
    }

    function testCannotDepositWETHInvalidAddress() external {
        uint256 amount = 1;
        address to = address(0);

        deal(_WETH, address(this), amount);

        vm.expectRevert(BrrETHManager.InvalidAddress.selector);

        manager.deposit(amount, to);
    }

    function testDepositWETH() external {
        uint256 amount = 1 ether;
        address to = address(this);

        deal(_WETH, address(this), amount);

        uint256 assetBalanceBefore = _COMET.balanceOf(address(vault));
        uint256 sharesBalanceBefore = vault.balanceOf(to);
        uint256 amountWithRoundingMargin = amount - 1;
        uint256 sharesPreview = vault.previewDeposit(amountWithRoundingMargin);

        vm.expectEmit(true, true, true, true, address(vault));

        emit ERC4626.Deposit(
            address(manager),
            to,
            amountWithRoundingMargin,
            sharesPreview
        );

        uint256 shares = manager.deposit(amount, to);

        assertEq(sharesPreview, shares);
        assertLe(
            _getAssets(assetBalanceBefore + amount),
            _COMET.balanceOf(address(vault))
        );
        assertEq(sharesBalanceBefore + shares, vault.balanceOf(to));
    }

    function testDepositWETHFuzz(uint80 amount, address to) external {
        vm.assume(amount >= _MIN_DEPOSIT && to != address(0));

        deal(_WETH, address(this), amount);

        uint256 assetBalanceBefore = _COMET.balanceOf(address(vault));
        uint256 sharesBalanceBefore = vault.balanceOf(to);
        uint256 shares = manager.deposit(amount, to);

        assertLe(
            _getAssets(assetBalanceBefore + amount),
            _COMET.balanceOf(address(vault))
        );
        assertEq(sharesBalanceBefore + shares, vault.balanceOf(to));
    }

    /*//////////////////////////////////////////////////////////////
                             redeem
    //////////////////////////////////////////////////////////////*/

    function testCannotRedeemInvalidAmount() external {
        uint256 shares = 0;
        address to = address(this);

        vm.expectRevert(BrrETHManager.InvalidAmount.selector);

        manager.redeem(shares, to);
    }

    function testCannotRedeemInvalidAddress() external {
        uint256 shares = 1;
        address to = address(0);

        vm.expectRevert(BrrETHManager.InvalidAddress.selector);

        manager.redeem(shares, to);
    }

    function testCannotRedeemRedeemMoreThanMax() external {
        address msgSender = address(this);
        uint256 shares = 1;
        address to = address(this);

        assertGt(shares, vault.balanceOf(msgSender));

        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);

        manager.redeem(shares, to);
    }

    function testRedeem() external {
        uint256 amount = 1 ether;

        vm.startPrank(address(this));

        deal(_WETH, address(this), amount);

        manager.deposit(amount, address(this));

        uint256 shares = vault.balanceOf(address(this));
        address to = address(this);
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 wethBalance = _WETH.balanceOf(to);
        uint256 assetsPreview = vault.previewRedeem(shares);

        vm.expectEmit(true, true, true, true, address(vault));

        emit ERC4626.Withdraw(
            address(manager),
            address(manager),
            address(this),
            assetsPreview,
            shares
        );

        uint256 assets = manager.redeem(shares, to);

        vm.stopPrank();

        // Comet rounds down, so we need to account for that.
        uint256 assetsWithErrorMargin = assets - 1;

        assertEq(assetsPreview, assets);
        assertEq(totalSupply - shares, vault.totalSupply());
        assertEq(totalAssets - assets, vault.totalAssets());
        assertEq(wethBalance + assetsWithErrorMargin, _WETH.balanceOf(to));
    }

    function testRedeemFuzz(
        uint80 amount,
        address msgSender,
        address to
    ) external {
        vm.assume(amount > _MIN_DEPOSIT);
        vm.assume(msgSender != address(0) && to != address(0));
        vm.startPrank(msgSender);

        deal(_WETH, msgSender, amount);

        _WETH.safeApproveWithRetry(address(manager), type(uint256).max);
        address(vault).safeApproveWithRetry(
            address(manager),
            type(uint256).max
        );

        manager.deposit(amount, msgSender);

        uint256 shares = vault.balanceOf(msgSender);
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 wethBalance = _WETH.balanceOf(to);
        uint256 assetsPreview = vault.previewRedeem(shares);

        vm.expectEmit(true, true, true, true, address(vault));

        emit ERC4626.Withdraw(
            address(manager),
            address(manager),
            msgSender,
            assetsPreview,
            shares
        );

        uint256 assets = manager.redeem(shares, to);

        vm.stopPrank();

        uint256 assetsWithErrorMargin = assets - 2;

        assertEq(assetsPreview, assets);
        assertEq(totalSupply - shares, vault.totalSupply());
        assertEq(totalAssets - assets, vault.totalAssets());

        // We're using `assertLe` here because in some cases Comet rounds down more than 1 wei.
        assertLe(wethBalance + assetsWithErrorMargin, _WETH.balanceOf(to));
    }
}
