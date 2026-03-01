// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/BabyNameMarket.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Simple ERC20 mock with public mint for testing
contract MockERC20 is ERC20 {
    uint8 private _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _dec = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

abstract contract TestHelpers is Test {
    BabyNameMarket public market;
    MockERC20 public token;

    address public owner = address(1);
    address public resolver = address(2);
    address public alice = address(3);
    address public bob = address(4);
    address public carol = address(5);

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_DEADLINE_OFFSET = 30 days;

    /// @notice 1 token unit in native decimals (1 USDC = 1e6)
    uint256 public constant ONE_UNIT = 1e6;

    function setUp() public virtual {
        // Deploy mock USDC (6 decimals)
        token = new MockERC20("USD Coin", "USDC", 6);

        vm.prank(owner);
        market = new BabyNameMarket(resolver, address(token));

        // Mint tokens and approve market for test users
        _fundUser(alice, 100_000 * ONE_UNIT);
        _fundUser(bob, 100_000 * ONE_UNIT);
        _fundUser(carol, 100_000 * ONE_UNIT);
        _fundUser(owner, 100_000 * ONE_UNIT);
    }

    function _fundUser(address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(market), type(uint256).max);
    }

    function _createTestCategory() internal returns (uint256) {
        string[] memory names = new string[](3);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";

        return market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Female,
            names,
            block.timestamp + DEFAULT_DEADLINE_OFFSET
        );
    }

    function _createTestCategoryMale() internal returns (uint256) {
        string[] memory names = new string[](3);
        names[0] = "Liam";
        names[1] = "Noah";
        names[2] = "Oliver";

        return market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Male,
            names,
            block.timestamp + DEFAULT_DEADLINE_OFFSET
        );
    }

    function _twoNames() internal pure returns (string[] memory) {
        string[] memory names = new string[](2);
        names[0] = "NameA";
        names[1] = "NameB";
        return names;
    }

    function _buyAs(address user, uint256 poolId, uint256 amount) internal {
        vm.prank(user);
        market.buy(poolId, amount);
    }
}
