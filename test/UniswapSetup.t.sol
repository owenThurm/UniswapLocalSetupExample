// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MUSD} from "../src/MUSD.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";

contract UniswapSetup is Test {

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    MUSD public musd;

    IUniswapV3Factory public constant uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISwapRouter public constant uniswapV3Router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant usdcWhale = 0xDa9CE944a37d218c3302F6B82a094844C6ECEb17;
    address public constant wethWhale = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
    address public constant daiWhale = 0x60FaAe176336dAb62e284Fe19B885B095d29fB7F;
    IERC20 public constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IUniswapV3Pool public musdDaiPool;

    function setUp() public {
        musd = new MUSD("MUSD", "MUSD", 18);

        // Deploy a direct Uniswap Pair for MUSD-usdc
        // Supported fee tiers are: 0.05%, 0.30%, and 1% measured out of 1e6,
        // we'll use 0.05% since this is a stablecoin pair
        // The tickspacing corresponding to this fee tier is 10.
        musdDaiPool = IUniswapV3Pool(uniswapV3Factory.createPool(address(musd), address(dai), 500));

        console.log("token 0: ", musdDaiPool.token0());
        console.log("token 1: ", musdDaiPool.token1());

        // price should be the sqrtPriceX96 at tick 0 == 1 * 2^96
        uint160 initialPrice = 79228162514264337593543950336;

        // initial price
        // initial liquidity amount
        // token 0 vs. token 1 stuff -> musd will be token0, usdc will be token1
        musdDaiPool.initialize(initialPrice);

        (, int24 tick, , , , , ) = musdDaiPool.slot0();

        console.logInt(tick);
    }


    function mintLiquidity() public {
        int24 lowerTick = -50;
        int24 upperTick = 50;
        // Provide liquidity for the new Uniswap pair, concentrate the liquidity around $1
        // ~$25M of concentrated liquidity, 25M MUSD & 25M DAI
        musdDaiPool.mint(address(this), lowerTick, upperTick, 1e28, "");
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        console.log(amount0, amount1);
        musd.mint(address(musdDaiPool), amount0);
        _mint(dai, address(musdDaiPool), amount1);
    }

    function _mint(IERC20 token, address to, uint256 amount) internal {
        if (address(token) == address(musd)) {
            musd.mint(to, amount);
            return;
        }

        if (token == usdc) {
            vm.prank(usdcWhale);
        } else if (token == weth) {
            vm.prank(wethWhale);
        } else if (token == dai) {
            vm.prank(daiWhale);
        } else {
            revert("<WRONG TOKEN>");
        }

        IERC20(token).transfer(to, amount);
    }

    function test_uniswapSwapForUsdc() public {
        mintLiquidity();
        _mint(musd, bob, 10 * 1e18);
        vm.startPrank(bob);

        assertTrue(musd.balanceOf(bob) == 10*1e18);
        assertTrue(usdc.balanceOf(bob) == 0);

        // Approve the router
        musd.approve(address(uniswapV3Router), type(uint256).max);

        // Let's swap MUSD to USDC
        bytes memory path = bytes.concat(
            bytes20(address(musd)),
            bytes3(uint24(500)), // fee tier for the pool is 0.05%
            bytes20(address(dai)),
            bytes3(uint24(500)),
            bytes20(address(usdc))
        );

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: bob,
            deadline: block.timestamp,
            amountIn: 10 * 1e18,
            amountOutMinimum: 9 * 1e6
        });

        // Perform swap
        uniswapV3Router.exactInput(params);

        assertTrue(musd.balanceOf(bob) == 0);
        assertTrue(usdc.balanceOf(bob) >= 99 * 1e5); // 0.99 USDC received
        assertTrue(usdc.balanceOf(bob) < 10 * 1e6); // Didn't quite get a full USDC due to fees & slippage
    }

    function test_uniswapSwapForWeth() public {
        mintLiquidity();
        _mint(musd, bob, 10 * 1e18);
        vm.startPrank(bob);

        assertTrue(musd.balanceOf(bob) == 10*1e18);
        assertTrue(weth.balanceOf(bob) == 0);

        // Approve the router
        musd.approve(address(uniswapV3Router), type(uint256).max);

        // Let's swap MUSD to USDC
        bytes memory path = bytes.concat(
            bytes20(address(musd)),
            bytes3(uint24(500)), // fee tier for the pool is 0.05%
            bytes20(address(dai)),
            bytes3(uint24(3000)), // fee tier for the dai-weth pool is 0.30%
            bytes20(address(weth))
        );

        // 10 / 2,000 = 0.005 ETH = 5 * 1e15
        // Should expect roughly 5 * 1e15 out

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: bob,
            deadline: block.timestamp,
            amountIn: 10 * 1e18,
            amountOutMinimum: 49 * 1e13 // depends on current price of ETH, should get roughly 1/2,000 = 0.0005 ETH at current prices
        });

        // Perform swap
        uniswapV3Router.exactInput(params);

        assertTrue(musd.balanceOf(bob) == 0);
        assertTrue(weth.balanceOf(bob) >= 49 * 1e14); // More than 0.0049 ETH received
        assertTrue(weth.balanceOf(bob) < 51 * 1e14); // Less than 0.0051 ETH received
    }
}
