//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V2_1} from "../src/AuctionSwap/AuctionSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address Teeah = 0x3288DCdcc0c8Fea3Cc84D463352d1DB7B22FCf1c;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        address pairAddress = 0xebeE32fAe4fCB913fA25aE16D741BA197510a575;

        vm.startBroadcast();

        Ratio_Swapping_Auctions_V2_1 swap = new Ratio_Swapping_Auctions_V2_1(
            StatToken,
            davToken,
            Teeah,
            governance,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
