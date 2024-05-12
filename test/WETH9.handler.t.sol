// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {LibAddressSet} from "./LibAddressSet.sol";
import {Test, console2} from "forge-std/Test.sol";
import {WETH9} from "../src/WETH9.sol";

contract PushEther {
    constructor(address weth) payable {
        selfdestruct(payable(weth));
    }
}

contract Handler is Test {
    using LibAddressSet for LibAddressSet.AddressSet;

    WETH9 public immutable WETH;
    uint256 public constant ETH_SUPPLY = 120_000_000 ether;

    address internal currentActor;
    LibAddressSet.AddressSet internal actors;

    // ghost variables
    uint256 public ghost_DepositSum;
    uint256 public ghost_WithdrawSum;
    uint256 public ghost_zeroDeposit;
    uint256 public ghost_pushedEther;
    uint256 public ghost_zeroWithdrawals;
    uint256 public ghost_zeroTransfers;
    uint256 public ghost_zeroTransferFrom;
    mapping(bytes32 => uint256) public ghost_Calls;

    error PayFailed();

    modifier createActor() {
        currentActor = msg.sender;
        actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorSeed) {
        currentActor = actors.rand(actorSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        ghost_Calls[key]++;
        _;
    }

    constructor(WETH9 weth) {
        WETH = weth;
        vm.deal(address(this), ETH_SUPPLY);
    }

    receive() external payable {}

    function deposit(uint256 amount) public createActor countCall("deposit") {
        amount = bound(amount, 0, address(this).balance);
        _pay(currentActor, amount);

        if (amount == 0) ghost_zeroDeposit++;

        vm.prank(currentActor, currentActor);
        WETH.deposit{value: amount}();

        ghost_DepositSum += amount;
    }

    function depositReceive(uint256 amount) public createActor countCall("depositReceive") {
        amount = bound(amount, 0, address(this).balance);
        _pay(currentActor, amount);

        if (amount == 0) ghost_zeroDeposit++;

        vm.prank(currentActor, currentActor);
        _pay(address(WETH), amount);

        ghost_DepositSum += amount;
    }

    function withdrawEth(uint256 amount, uint256 actorSeed) public useActor(actorSeed) countCall("withdrawEth") {
        amount = bound(amount, 0, WETH.balanceOf(currentActor));

        if (amount == 0) ghost_zeroWithdrawals++;

        vm.startPrank(currentActor, currentActor);
        WETH.withdraw(amount);
        _pay(address(this), amount);
        vm.stopPrank();

        ghost_WithdrawSum += amount;
    }

    function approve(address spender, uint256 allowance, uint256 actorSeed)
        public
        useActor(actorSeed)
        countCall("approve")
    {
        allowance = bound(allowance, 0, type(uint256).max);

        vm.prank(currentActor, currentActor);
        WETH.approve(spender, allowance);
    }

    function transfer(uint256 actorSeed, uint256 recipientSeed, uint256 amount)
        public
        useActor(actorSeed)
        countCall("transfer")
    {
        amount = bound(amount, 0, WETH.balanceOf(currentActor));
        address recipient = actors.rand(recipientSeed);

        if (amount == 0) ghost_zeroTransfers++;

        vm.prank(currentActor, currentActor);
        WETH.transfer(recipient, amount);
    }

    function transferFrom(uint256 actorSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount)
        public
        useActor(actorSeed)
        countCall("transferFrom")
    {
        amount = bound(amount, 0, WETH.balanceOf(currentActor));
        address spender = actors.rand(spenderSeed);
        address recipient = actors.rand(recipientSeed);

        if (amount == 0) ghost_zeroTransferFrom++;

        vm.prank(currentActor, currentActor);
        WETH.approve(spender, amount);

        vm.prank(spender, spender);
        WETH.transferFrom(currentActor, recipient, amount);
    }

    function pushEther(uint256 amount) public countCall("pushEther") {
        amount = bound(amount, 0, address(this).balance);
        new PushEther{value: amount}(address(WETH));
        ghost_pushedEther += amount;
    }

    // ========================================= HELPERS ========================================= //

    function _pay(address to, uint256 amount) internal {
        (bool sent, bytes memory data) = to.call{value: amount}(new bytes(0));

        if (!sent) {
            if (data.length == 0) {
                revert PayFailed();
            } else {
                // Frequent revert reason:
                // Reason: type check failed for "VmCalls" with data
                assembly {
                    revert(add(32, data), mload(data))
                }
            }
        }
    }

    function forEachActor(function(address) external view func) public view {
        actors.forEach(func);
    }

    function reduceActors(uint256 accumulator, function(uint256,address) external view returns (uint256) func)
        public
        view
        returns (uint256)
    {
        return actors.reduce(accumulator, func);
    }
}
