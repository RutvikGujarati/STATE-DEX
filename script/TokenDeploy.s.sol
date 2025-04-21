// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Yees.sol";

contract DeployState is Script {
    function run() external {
        vm.startBroadcast();
        address Five = 0xBAaB2913ec979d9d21785063a0e4141e5B787D28;
        address Swap = 0x90Cbf8c9eC758ad26Fd3cd4B4F2B601425d4A04E;
        Yees state = new Yees(
                "Yees",
                "Yees",
                Five,
                Swap
            );

        console.log("rievaollar deployed at:", address(state));

        vm.stopBroadcast();
    }
}
//0x27650912642DBb46677408CC14A97Afb8A2e11c5