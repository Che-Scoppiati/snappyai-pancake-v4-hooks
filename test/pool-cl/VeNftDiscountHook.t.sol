// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {Test} from "forge-std/Test.sol";
import {Constants} from "@pancakeswap/v4-core/test/pool-cl/helpers/Constants.sol";
import {Currency} from "@pancakeswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {CLPoolParametersHelper} from "@pancakeswap/v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {VeNftDiscountHook} from "../../src/pool-cl/VeNftDiscountHook.sol";
import {CLTestUtils} from "./utils/CLTestUtils.sol";
import {CLPoolParametersHelper} from "@pancakeswap/v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {PoolIdLibrary} from "@pancakeswap/v4-core/src/types/PoolId.sol";
import {ICLSwapRouterBase} from "@pancakeswap/v4-periphery/src/pool-cl/interfaces/ICLSwapRouterBase.sol";
import {LPFeeLibrary} from "@pancakeswap/v4-core/src/libraries/LPFeeLibrary.sol";

contract VeNftDiscountHookTest is Test, CLTestUtils {
    using PoolIdLibrary for PoolKey;
    using CLPoolParametersHelper for bytes32;

    VeNftDiscountHook hook;
    Currency currency0;
    Currency currency1;
    PoolKey key;
    // MockERC20 veCake = new MockERC20("veCake", "veCake", 18);
    MockERC721 veNft = new MockERC721("veNft", "veNft");
    address alice = makeAddr("alice");

    function setUp() public {
        (currency0, currency1) = deployContractsWithTokens();
        // hook = new VeNftDiscountHook(poolManager, address(veCake));
        hook = new VeNftDiscountHook(poolManager, address(veNft));

        // create the pool key
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });

        // initialize pool at 1:1 price point and set 3000 as initial lp fee, lpFee is stored in the hook
        poolManager.initialize(key, Constants.SQRT_RATIO_1_1, abi.encode(uint24(3000)));

        // add liquidity so that swap can happen
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 100 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 100 ether);
        addLiquidity(key, 100 ether, 100 ether, -60, 60);

        // approve from alice for swap in the test cases below
        vm.startPrank(alice);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // mint alice token for trade later
        MockERC20(Currency.unwrap(currency0)).mint(address(alice), 100 ether);
    }

    function testVeNftHolder() public {
        // mint alice veCake
        // veCake.mint(address(alice), 1 ether);
        veNft.mint(address(alice), 1);

        uint256 amtOut = _swap();
        console.log("Holder amount %d", amtOut);

        // amt out should be close to 1 ether minus slippage
        assertGe(amtOut, 0.997 ether);
    }

    function testNonVeNftHolderXX() public {
        uint256 amtOut = _swap();

        console.log("Non holder amount %d", amtOut);

        // amt out be at least 0.3% lesser due to swap fee
        assertLe(amtOut, 0.997 ether);
    }

    function _swap() internal returns (uint256 amtOut) {
        // set alice as tx.origin
        vm.prank(address(alice), address(alice));

        amtOut = swapRouter.exactInputSingle(
            ICLSwapRouterBase.V4CLExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                recipient: address(alice),
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
                hookData: new bytes(0)
            }),
            block.timestamp
        );
    }
}
