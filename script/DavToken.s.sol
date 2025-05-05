// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Decentralized_Autonomous_Vaults_DAV_V2_1} from "../src/MainTokens/DavToken.sol";

contract ScriptDAV is Script {
    function run() external {
        vm.startBroadcast();

        address liquidity = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;
        address DAVWallet = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;
		address state = 0xbF37E50b0a0579518Ea68beC6D7f7b8AC949E4C9;
        address Governanace = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;

        Decentralized_Autonomous_Vaults_DAV_V2_1 dav = new Decentralized_Autonomous_Vaults_DAV_V2_1(
                liquidity,
                DAVWallet,
                state,
				Governanace,
                "pDAV",
                "pDAV"
            );

        console.log("Contract deployed at:", address(dav));

        vm.stopBroadcast();
    }
}
//0x6F97Abbf8098b4E3A3ed41F2f10F512D92c3f15A