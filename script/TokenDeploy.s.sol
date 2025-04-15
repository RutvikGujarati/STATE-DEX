// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Yees.sol";

contract DeployState is Script {
    function run() external {
        vm.startBroadcast();
        address Five = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;
        address Swap = 0x59589F149e9022f58E446d4A20a014c42541cA31;
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