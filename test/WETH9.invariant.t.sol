// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {WETH9} from "../src/WETH9.sol";
import {Handler} from "./WETH9.handler.t.sol";

contract Invariant is Test {
    Handler private handler;
    WETH9 private weth;

    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.depositReceive.selector;
        selectors[2] = Handler.withdrawEth.selector;
        selectors[3] = Handler.approve.selector;
        selectors[4] = Handler.transfer.selector;
        selectors[5] = Handler.transferFrom.selector;
        selectors[6] = Handler.pushEther.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        excludeSender(address(handler));
    }

    ///////////////////////////////////////////////////////////////////////
    ////////////////////////////// IMPORTANT //////////////////////////////
    ///////////////////////////////////////////////////////////////////////
    // WETH keep tracks of the total supply by reading the balance in the contract
    // and not with internal accounting in the form of an state variable. This
    // open to the possibility that the total supply will not be equal to the
    // sum of deposites and sum of balances because ether can be forced into the
    // contract with the SELFDESTRUCT opcode.

    // Conservation of Ether states ETH can only by wrap to WETH, WETH can only be
    // unwrapped to ETH. The summof balance of the handler plus WETH total supply must
    // be equal to total supply of ETH.
    function invariant__ConservationOfEther() public view {
        assertEq(handler.ETH_SUPPLY(), address(handler).balance + weth.totalSupply());
    }

    // Solvency of Deposits states the balance of WETH must be equal to the difference
    // between deposit and withdrawals at all time. This means every deposited ETH must
    // be withdrawable.
    function invariant__SolvencyDeposits() public view {
        assertEq(
            address(weth).balance,
            handler.ghost_DepositSum() + handler.ghost_pushedEther() - handler.ghost_WithdrawSum()
        );
    }

    // Solvency of Balances state the sum of all individual WETH balances must be equal
    // to the ETH balances in the WETH contract. This means the contract must be able
    // to handle all withdrawals.
    function invariant__SolvencyBalances() public view {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalances);
        assertEq(address(weth).balance - handler.ghost_pushedEther(), sumOfBalances);
    }

    // Depositor Balance state that no individual WETH balance can't be greater than
    // the total supply of WETH.
    function invariant__DepositorBalance() public view {
        handler.forEachActor(this.assertNoIndividualBalanceIsGreaterThanWethTotalSupply);
    }

    // Summary of calls in the campaign
    function invariant__CallSummary() public view {
        console2.log("Call Summary:");
        console2.log("========================");
        console2.log("deposit", handler.ghost_Calls("deposit"));
        console2.log("depositReceive", handler.ghost_Calls("depositReceive"));
        console2.log("withdrawEth", handler.ghost_Calls("withdrawEth"));
        console2.log("approve", handler.ghost_Calls("approve"));
        console2.log("transfer", handler.ghost_Calls("transfer"));
        console2.log("transferFrom", handler.ghost_Calls("transferFrom"));
        console2.log("========================");
        console2.log("zeroDeposits", handler.ghost_zeroDeposit());
        console2.log("zeroWithdrawals", handler.ghost_zeroWithdrawals());
        console2.log("zeroTransfers", handler.ghost_zeroTransfers());
        console2.log("zeroTransferFrom", handler.ghost_zeroTransferFrom());
    }

    // ========================================= HELPERS ========================================= //

    function accumulateBalances(uint256 balance, address account) external view returns (uint256) {
        return balance + weth.balanceOf(account);
    }

    function assertNoIndividualBalanceIsGreaterThanWethTotalSupply(address account) external view {
        assertLe(weth.balanceOf(account), weth.totalSupply());
    }
}
