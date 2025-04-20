// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StateLP.sol";

contract DeployDeepState is Script {
    function run() external {
        vm.startBroadcast();
        address _state = 0x114bd5De4D724A0CcB2e28D1657B83B5b05d37D5;

        StateLP sp = new StateLP(_state);

        console.log("StateLP deployed at:", address(sp));

        vm.stopBroadcast();
    }
}
//0xD19afEF6772B9b5E9a8Cf527D77241e9ceD6C2be
