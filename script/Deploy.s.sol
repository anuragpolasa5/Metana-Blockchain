// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BatchCallDelegation7702} from "../src/BatchCallDelegation7702.sol";
import {Counter} from "../src/Counter.sol";
import {SimpleToken} from "../src/SimpleToken.sol";

/**
 * @title DeployScript
 * @notice Deploys BatchCallDelegation7702, Counter, and SimpleToken to a testnet.
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --private-key <KEY>
 */
contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy BatchCallDelegation7702
        BatchCallDelegation7702 batchCaller = new BatchCallDelegation7702();
        console.log("BatchCallDelegation7702 deployed at:", address(batchCaller));

        // Deploy Counter
        Counter counter = new Counter();
        console.log("Counter deployed at:", address(counter));

        // Deploy SimpleToken with 1,000,000 initial supply
        SimpleToken token = new SimpleToken(1_000_000);
        console.log("SimpleToken deployed at:", address(token));

        vm.stopBroadcast();
    }
}
