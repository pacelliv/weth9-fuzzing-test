# Invariants

The WETH contract allows deposit, transfers and withdrawals of zero value.

## On deposit

1. If `msg.value` > 0, depositor's WETH balance MUST increase, otherwise balance MUST remain the same
2. If `msg.value` > 0, WETH total supply MUST increase, otherwise total supply MUST remain the same
3. If `msg.value` > 0, depositor's native balance MUST decrease, otherwise balance MUST remain the same
4. If `msg.value` > 0, WETH's native balance MUST increase, otherwise balance MUST remain the same

## On withdraw

1. If `amount` > 0, depositor's WETH balance MUST decrease, otherwise balance MUST remain the same
2. If `amount` > 0, WETH total supply MUST decrease, otherwise total supply MUST remain the same
3. If `amount` > 0, depositor's native balance MUST increase, otherwise balance MUST remain the same
4. If `amount` > 0, WETH's native balance MUST decrease, otherwise balance MUST remain the same

## On transfer

1. If `amount` > 0, sender's WETH balance MUST decrease, otherwise balance MUST remain the same
2. If `amount` > 0, recipient's WETH balance MUST increase, otherwise balance MUST remain the same
3. Transfer of WETH SHOULD NOT have any effect on WETH total supply
4. Transfer of WETH SHOULD NOT have any effect on WETH's native balance
5. Transfer of WETH SHOULD NOT have any effect on sender's native balance
6. Transfer of WETH SHOULD NOT have any effect on recipient's native balance

## On approve

1. If `allowance` > 0, spender`s allowance MUST be greater than zero, othersiwe MUST be zero
2. Approve an spender SHOULD not have any effect on caller's allowance
3. Approval of WETH SHOULD NOT have any effect on WETH total supply
4. Approval of WETH SHOULD NOT have any effect on WETH's native balance
5. Approval of WETH SHOULD NOT have any effect on owner's native balance
6. Approval of WETH SHOULD NOT have any effect on spender's native balance

## On transferFrom

1. If `amount` > 0, from's WETH balance MUST decrease, otherwise balance MUST remain the same
2. If `amount` > 0, to's WETH balance MUST increase, otherwise balance MUST remain the same
3. If caller is an approved third party, then the allowance MUST decrease by the amount transferred
4. Transfer of WETH SHOULD NOT have any effect on WETH total supply
5. Transfer of WETH SHOULD NOT have any effect on WETH's native balance
6. Transfer of WETH SHOULD NOT have any effect on sender's native balance
7. Transfer of WETH SHOULD NOT have any effect on recipient's native balance

## View methods

1. These methods CANNOT revert
