//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V2_1} from "../src/AuctionSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address governance = 0xBAaB2913ec979d9d21785063a0e4141e5B787D28;

        vm.startBroadcast();

        Ratio_Swapping_Auctions_V2_1 swap = new Ratio_Swapping_Auctions_V2_1(
            governance
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}

//0x59589F149e9022f58E446d4A20a014c42541cA31