// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Decentralized_Autonomous_Vaults_DAV_V2_1} from "../src/MainTokens/DavToken.sol";

contract ScriptDAV is Script {
    function run() external {
        vm.startBroadcast();

        address liquidity = 0xBAaB2913ec979d9d21785063a0e4141e5B787D28;
        address DAVWallet = 0x5E19e86F1D10c59Ed9290cb986e587D2541e942C;
		address state = 0x9b33fAb8F5241B9A2D9028F671e2886db4dbd49E;
        address Governanace = 0xBAaB2913ec979d9d21785063a0e4141e5B787D28;

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