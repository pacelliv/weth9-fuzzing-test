// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {LibAddressSet} from "./LibAddressSet.sol";
import {WETH9} from "../src/WETH9.sol";

// IMPORTANT: this fuzzing campaign excludes forcing ETH into WETH using the SELFDESTRUCT opcode

contract User {
    receive() external payable {}

    function proxy(address target, bytes calldata payload) public returns (bool success, bytes memory data) {
        (success, data) = target.call(payload);
    }

    function proxyWithValue(address target, uint256 value, bytes calldata payload)
        public
        returns (bool success, bytes memory data)
    {
        (success, data) = target.call{value: value}(payload);
    }

    function sendValue(address target) public returns (bool success, bytes memory data) {
        (success, data) = target.call{value: address(this).balance}("");
    }
}

contract PushEther {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract EchidnaWETH9Tester {
    using LibAddressSet for LibAddressSet.AddressSet;

    WETH9 private immutable WETH;
    uint256 private constant ETH_SUPPLY = 120000000 ether; // 120 M
    User private currentActor;
    LibAddressSet.AddressSet private actors;

    // ghost variables
    uint256 private ghost_SumDeposits;
    uint256 private ghost_SumWithdrawals;
    uint256 private ghost_PushedEther;

    event DebugAddress(address account);
    event DebugAddresses(address account1, address account2);
    event DebugValue(uint256 val);
    event DebugValues(uint256 val1, uint256 val2);

    modifier createActor() {
        currentActor = new User();
        actors.add(address(currentActor));
        _;
    }

    modifier useActor(uint256 actorSeed) {
        currentActor = User(payable(actors.rand(actorSeed)));
        _;
    }

    constructor() payable {
        WETH = new WETH9();
    }

    receive() external payable {}

    // function forceEther(uint256 amount) public {
    //     require(address(this).balance > 0);
    //     amount = _bound(amount, 1, address(this).balance);
    //     ghost_PushedEther += amount;
    //     new PushEther{value: amount}(payable(address(WETH)));
    // }

    function wrapZero() public createActor {
        // Pre-conditions: not necessary bc we're wrapping zero ether

        // State before deposit
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 wethEthBalanceBefore = address(WETH).balance;

        // Action: wrap ether
        (bool success,) = currentActor.proxyWithValue(address(WETH), 0, abi.encodeWithSelector(WETH.deposit.selector));
        require(success);

        ghost_SumDeposits += 0;

        // Post-conditions: assert invariants
        if (success) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;

            // Invariants:
            // 1. Wrapping zero ETH CANNOT increase WETH total supply
            assert(wethSupplyAfter == wethSupplyBefore);
            // 2. Wrapping zero ETH CANNOT decrease depositor's ETH balance
            assert(actorEthBalanceAfter == actorEthBalanceBefore);
            // 3. Wrapping zero ETH CANNOT increase depositor's WETH balance
            assert(actorWethBalanceAfter == actorWethBalanceBefore);
            // 4. Wrapping zero ETH CANNOT increase WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 5. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 6. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 7. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    // This function exclude deposits of zero value
    function wrap(uint256 amount) public createActor {
        // Pre-conditions: bound input space, fund actor
        require(address(this).balance > 0);
        amount = _bound(amount, 1, address(this).balance);
        _payUser(address(currentActor), amount);

        // State before deposit
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 wethEthBalanceBefore = address(WETH).balance;

        // Action: wrap ether
        (bool success,) =
            currentActor.proxyWithValue(address(WETH), amount, abi.encodeWithSelector(WETH.deposit.selector));
        require(success);

        ghost_SumDeposits += amount;

        // Post-conditions: assert invariants
        if (success) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;

            // Invariants:
            // 1. Wrapping ETH MUST increase WETH total supply
            assert(wethSupplyAfter > wethSupplyBefore);
            // 2. Wrapping ETH MUST decrease depositor's ETH balance
            assert(actorEthBalanceAfter < actorEthBalanceBefore);
            // 3. Wrapping ETH MUST increase depositor's WETH balance
            assert(actorWethBalanceAfter > actorWethBalanceBefore);
            // 4. Wrapping ETH MUST increase WETH's ETH balance
            assert(wethEthBalanceAfter > wethEthBalanceBefore);
            // 5. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 6. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 7. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    function unwrapZero(uint256 actorSeed) public useActor(actorSeed) {
        // Pre-conditions: not necessary bc we're unwrapping zero ETH

        // State before withdrawal
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 wethEthBalanceBefore = address(WETH).balance;

        // Action: unwrap ether
        (bool success,) = currentActor.proxy(address(WETH), abi.encodeWithSelector(WETH.withdraw.selector, 0));
        require(success);

        ghost_SumWithdrawals += 0;

        if (success) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;

            // Invariants:
            // 1. Unwrapping zero ETH CANNOT decrease WETH total supply
            assert(wethSupplyAfter == wethSupplyBefore);
            // 2. Unwrapping zero ETH CANNOT increase user's ETH balance
            assert(actorEthBalanceAfter == actorEthBalanceBefore);
            // 3. Unwrapping zero ETH CANNOT decrease user's WETH balance
            assert(actorWethBalanceAfter == actorWethBalanceBefore);
            // 4. Unwrapping zero ETH CANNOT decrease WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 5. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 6. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits + ghost_PushedEther);
            // 7. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    function unwrap(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        // Pre-conditions: bound input space, assert user's WETH balance is greater than zero
        require(WETH.balanceOf(address(currentActor)) > 0);
        amount = _bound(amount, 1, WETH.balanceOf(address(currentActor)));

        // State before withdrawal
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 wethEthBalanceBefore = address(WETH).balance;

        // Action: unwrap ether and send ether from actor to this contract
        (bool success1,) = currentActor.proxy(address(WETH), abi.encodeWithSelector(WETH.withdraw.selector, amount));
        require(success1);

        uint256 actorEthBalanceAfter = address(currentActor).balance;

        // Invariant: unwrapping ETH MUST increase user's ETH balance
        assert(actorEthBalanceAfter > actorEthBalanceBefore);

        (bool success2,) = currentActor.sendValue(address(this));
        require(success2);

        ghost_SumWithdrawals += amount;

        if (success1 && success2) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;

            // Invariants:
            // 1. Unwrapping ETH MUST decrease WETH total supply
            assert(wethSupplyAfter < wethSupplyBefore);
            // 2. Unwrapping ETH MUST decrease user's WETH balance
            assert(actorWethBalanceAfter < actorWethBalanceBefore);
            // 3. Unwrapping ETH MUST decrease WETH's ETH balance
            assert(wethEthBalanceAfter < wethEthBalanceBefore);
            // 4. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 5. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 6. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    function approve(uint256 actorSeed, uint256 spenderSeed, uint256 allowance) public {
        // Pre-conditions: get actors
        User owner = User(payable(actors.rand(actorSeed)));
        address spender = actors.rand(spenderSeed);

        // State before approval
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 wethEthBalanceBefore = address(WETH).balance;

        // Action: approve spender
        (bool success,) = owner.proxy(address(WETH), abi.encodeWithSelector(WETH.approve.selector, spender, allowance));
        require(success);

        // Post-conditions: assert invariants
        if (success) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;

            // Invariants:
            // 1. Approving spender SHOULD NOT change WETH total supply
            assert(wethSupplyAfter == wethSupplyBefore);
            // 2. Approving spender SHOULD NOT change depositor's ETH balance
            assert(actorEthBalanceAfter == actorEthBalanceBefore);
            // 3. Approving spender SHOULD NOT change depositor's WETH balance
            assert(actorWethBalanceAfter == actorWethBalanceBefore);
            // 4. Approving spender SHOULD NOT change WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 5. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 6. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 7. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
            // 8. Assert spender's allowance
            assert(WETH.allowance(address(owner), spender) == allowance);
        }
    }

    function transferZero(uint256 actorSeed, uint256 toSeed) public useActor(actorSeed) {
        // Pre-conditions: get to address
        address to = actors.rand(toSeed);
        require(to != address(currentActor));

        // State before transfer
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 wethEthBalanceBefore = address(WETH).balance;
        uint256 toWethBalanceBefore = WETH.balanceOf(address(to));

        // Action: transfer WETH
        (bool success,) = currentActor.proxy(address(WETH), abi.encodeWithSelector(WETH.transfer.selector, to, 0));
        require(success);

        // Post-conditions: assert invariants
        if (success) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;
            uint256 toWethBalanceAfter = WETH.balanceOf(to);

            // Invariants:
            // 1. Transferring zero WETH SHOULD NOT change WETH total supply
            assert(wethSupplyAfter == wethSupplyBefore);
            // 2. Transferring zero WETH SHOULD NOT change depositor's ETH balance
            assert(actorEthBalanceAfter == actorEthBalanceBefore);
            // 3. Transferring zero WETH SHOULD NOT change sender's WETH balance
            assert(actorWethBalanceAfter == actorWethBalanceBefore);
            // 4. Transferring zero WETH SHOULD NOT change to's WETH balance
            assert(toWethBalanceAfter == toWethBalanceBefore);
            // 5. Transferring zero WETH SHOULD NOT change WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 6. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 7. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 8. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    function transfer(uint256 actorSeed, uint256 toSeed, uint256 amount) public useActor(actorSeed) {
        // Pre-conditions: get to address and scope input space
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        require(actorWethBalanceBefore > 0);
        amount = _bound(amount, 1, actorWethBalanceBefore);
        address to = actors.rand(toSeed);
        require(to != address(currentActor));

        // State before transfer
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 wethEthBalanceBefore = address(WETH).balance;
        uint256 toWethBalanceBefore = WETH.balanceOf(address(to));

        // Action: transfer WETH
        (bool success,) = currentActor.proxy(address(WETH), abi.encodeWithSelector(WETH.transfer.selector, to, amount));
        require(success);

        // Post-conditions: assert invariants
        if (success) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;
            uint256 toWethBalanceAfter = WETH.balanceOf(to);

            // Invariants:
            // 1. Transferring WETH SHOULD NOT change WETH total supply
            assert(wethSupplyAfter == wethSupplyBefore);
            // 2. Transferring WETH SHOULD NOT change depositor's ETH balance
            assert(actorEthBalanceAfter == actorEthBalanceBefore);
            // 3. Transferring WETH MUST decrease sender's WETH balance
            assert(actorWethBalanceAfter < actorWethBalanceBefore);
            // 4. Transferring WETH MUST increase to's WETH balance
            assert(toWethBalanceAfter > toWethBalanceBefore);
            // 5. Transferring WETH SHOULD NOT change WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 6. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 7. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 8. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    function transferFromZero(uint256 actorSeed, uint256 spenderSeed, uint256 toSeed) public useActor(actorSeed) {
        // Pre-conditions: get to address
        address to = actors.rand(toSeed);
        address spender = actors.rand(spenderSeed);
        require(to != address(currentActor));
        require(spender != to);

        // State before approval
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 wethEthBalanceBefore = address(WETH).balance;
        uint256 toWethBalanceBefore = WETH.balanceOf(address(to));

        // Action: approve spender
        (bool success1,) =
            currentActor.proxy(address(WETH), abi.encodeWithSelector(WETH.approve.selector, spender, type(uint256).max));
        require(success1);

        // Action: transfer WETH
        (bool success2,) = User(payable(spender)).proxy(
            address(WETH), abi.encodeWithSelector(WETH.transferFrom.selector, address(currentActor), to, 0)
        );
        require(success2);

        // Post-conditions: assert invariants
        if (success1 && success2) {
            uint256 wethSupplyAfter = WETH.totalSupply();
            uint256 actorEthBalanceAfter = address(currentActor).balance;
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;
            uint256 toWethBalanceAfter = WETH.balanceOf(to);

            // Invariants:
            // 1. Transferring zero WETH SHOULD NOT change WETH total supply
            assert(wethSupplyAfter == wethSupplyBefore);
            // 2. Transferring zero WETH SHOULD NOT change depositor's ETH balance
            assert(actorEthBalanceAfter == actorEthBalanceBefore);
            // 3. Transferring zero WETH SHOULD NOT change sender's WETH balance
            assert(actorWethBalanceAfter == actorWethBalanceBefore);
            // 4. Transferring zero WETH SHOULD NOT change to's WETH balance
            assert(toWethBalanceAfter == toWethBalanceBefore);
            // 5. Transferring zero WETH SHOULD NOT change WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 6. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 7. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 8. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
        }
    }

    function transferFrom(uint256 actorSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount)
        public
        useActor(actorSeed)
    {
        // Pre-conditions: get to address
        address to = actors.rand(toSeed);
        address spender = actors.rand(spenderSeed);
        require(to != address(currentActor));
        require(spender != to);

        // State before transfer
        uint256 wethSupplyBefore = WETH.totalSupply();
        uint256 actorWethBalanceBefore = WETH.balanceOf(address(currentActor));
        uint256 actorEthBalanceBefore = address(currentActor).balance;
        uint256 wethEthBalanceBefore = address(WETH).balance;
        uint256 toWethBalanceBefore = WETH.balanceOf(address(to));

        // Action: approve spender
        (bool success1,) =
            currentActor.proxy(address(WETH), abi.encodeWithSelector(WETH.approve.selector, spender, amount));
        require(success1);

        uint256 spenderAllowanceBefore = WETH.allowance(address(currentActor), spender);

        // Action: transfer WETH
        (bool success2,) = User(payable(spender)).proxy(
            address(WETH), abi.encodeWithSelector(WETH.transferFrom.selector, address(currentActor), to, 0)
        );
        require(success2);

        // Post-conditions: assert invariants
        if (success1 && success2) {
            uint256 actorWethBalanceAfter = WETH.balanceOf(address(currentActor));
            uint256 wethEthBalanceAfter = address(WETH).balance;
            uint256 toWethBalanceAfter = WETH.balanceOf(to);
            uint256 spenderAllowanceAfter = WETH.allowance(address(currentActor), spender);

            // Invariants:
            // 1. Transferring WETH SHOULD NOT change WETH total supply
            assert(WETH.totalSupply() == wethSupplyBefore);
            // 2. Transferring WETH SHOULD NOT change depositor's ETH balance
            assert(address(currentActor).balance == actorEthBalanceBefore);
            // 3. Transferring WETH MUST decrease change from's WETH balance
            assert(actorWethBalanceAfter == actorWethBalanceBefore);
            // 4. Transferring WETH MUST increase to's WETH balance
            assert(toWethBalanceAfter == toWethBalanceBefore);
            // 5. Transferring WETH SHOULD NOT change WETH's ETH balance
            assert(wethEthBalanceAfter == wethEthBalanceBefore);
            // 6. Convervation of Ether: ETH can only be wrapped to WETH and WETH can only be unwrapped to ETH
            assert(ETH_SUPPLY == address(this).balance + WETH.totalSupply());
            // 7. Solvency deposits: all deposited ETH MUST be withdrawable
            assert(address(WETH).balance == ghost_SumDeposits - ghost_SumWithdrawals);
            // 8. Solvency balances: sum of individual WETH balance must be equal to WETH's ETH balance
            assert(address(WETH).balance == _reduceUsersWethBalance());
            // 9. Spender allowance MUST decrease after moving tokens on behalf of owner
            assert(spenderAllowanceAfter < spenderAllowanceBefore);
        }
    }

    // ========================================= HELPERS ========================================= //

    function _payUser(address user, uint256 amount) internal {
        (bool success,) = user.call{value: amount}("");
        require(success, "pay to user failed");
    }

    function _reduceUsersWethBalance() internal view returns (uint256 balancesSum) {
        address[] memory users = actors.actors;

        for (uint256 i; i < users.length; i++) {
            balancesSum += WETH.balanceOf(users[i]);
        }
    }

    function _bound(uint256 amount, uint256 min, uint256 max) internal pure returns (uint256) {
        return min + (amount % (max - min + 1));
    }
}
