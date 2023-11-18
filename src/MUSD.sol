// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MUSD is ERC20 {

    error NotHandler(address caller);

    mapping(address => bool) isHandler;

    uint8 private immutable _decimals;

    modifier onlyHandler {
        if (!isHandler[msg.sender]) revert NotHandler(msg.sender);
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
        isHandler[msg.sender] = true;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyHandler {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyHandler {
        _burn(from, amount);
    }

}