# WETH9 Fuzzing Test

This repo includes fuzzing campaigns to test the WETH contract deployed at: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` on mainnet.

The campaigns are written using Foundry and Echidna.

The WETH contract was slightly modified to use pragma `0.8.22`.

## Run the campaigns

Run Echidna campaign:

```js
echidna test/echidna/EchidnaWETH9Tester.sol --contract EchidnaWETH9Tester --config test/echidna/weth9.yaml
```

Run Foundry campaign:

```js
forge test
```
