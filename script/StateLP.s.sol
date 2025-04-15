// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StateLP.sol";

contract DeployDeepState is Script {
    function run() external {
 
        vm.startBroadcast();

       StateLP sp = new StateLP(treasuryWallet);

        console.log("StateLP deployed at:", address(sp));

        vm.stopBroadcast();
    }
}