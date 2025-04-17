// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StateLP.sol";

contract DeployDeepState is Script {
    function run() external {
        vm.startBroadcast();
        address _state = 0x114bd5De4D724A0CcB2e28D1657B83B5b05d37D5;
        address _wpls = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
        address _pairAddress = 0xF15f1F64891A3e2797328445CB28Ba11Fe468505;

        address _governance = 0xBAaB2913ec979d9d21785063a0e4141e5B787D28;
        StateLP sp = new StateLP(_state, _wpls, _pairAddress, _governance);

        console.log("StateLP deployed at:", address(sp));

        vm.stopBroadcast();
    }
}
//0xD19afEF6772B9b5E9a8Cf527D77241e9ceD6C2be