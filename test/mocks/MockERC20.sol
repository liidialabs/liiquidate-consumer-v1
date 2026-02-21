// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing
 * @dev Provides functionality for minting, burning, and basic ERC20 operations
 */
contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event ApprovalUpdated(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /**
     * @notice Initializes the mock token with a name, symbol, and decimals
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param decimals_ The number of decimal places for the token
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimals_;
    }

    /**
     * @notice Returns the number of decimal places for the token
     * @return The decimal places
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mints tokens to a specified address
     * @param to The address to receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than zero");
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Mints arbitrary amount of tokens to an address (for testing flexibility)
     * @param to The address to receive tokens
     * @param amount The amount to mint
     */
    function mintTo(address to, uint256 amount) external {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than zero");
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Burns tokens from a specified address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external {
        require(from != address(0), "Cannot burn from zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(balanceOf(from) >= amount, "Insufficient balance to burn");
        _burn(from, amount);
        emit Burned(from, amount);
    }

    /**
     * @notice Burns tokens from the caller's balance
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external {
        require(account != address(0), "Cannot burn from zero address");
        require(amount > 0, "Amount must be greater than zero");

        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "Insufficient allowance");

        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
        emit Burned(account, amount);
    }

    /**
     * @notice Sets approval for a spender (override for testing)
     * @param spender The address that can spend tokens
     * @param amount The amount of tokens that can be spent
     */
    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        emit ApprovalUpdated(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Gets the balance of an account
     * @param account The account to check
     * @return The balance of the account
     */
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @notice Gets the total supply of the token
     * @return The total supply
     */
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @notice Gets the allowance of a spender for an owner
     * @param owner The owner of the tokens
     * @param spender The spender of the tokens
     * @return The allowance amount
     */
    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }

    /**
     * @notice Transfers tokens from one address to another
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     * @return success True if the transfer was successful
     */
    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Transfers tokens on behalf of an owner
     * @param from The owner's address
     * @param to The recipient's address
     * @param amount The amount of tokens to transfer
     * @return success True if the transfer was successful
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(from, to, amount);
        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "Insufficient allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        return true;
    }

    /**
     * @notice Increases approval for a spender
     * @param spender The spender's address
     * @param addedValue The amount to increase the allowance by
     * @return success True if the increase was successful
     */
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        _approve(msg.sender, spender, currentAllowance + addedValue);
        return true;
    }

    /**
     * @notice Decreases approval for a spender
     * @param spender The spender's address
     * @param subtractedValue The amount to decrease the allowance by
     * @return success True if the decrease was successful
     */
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(
            currentAllowance >= subtractedValue,
            "Decreased allowance below zero"
        );
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    /**
     * @notice Helper function to initialize user balance for testing
     * @param account The account to initialize
     * @param amount The initial balance amount
     */
    function setBalance(address account, uint256 amount) external onlyOwner {
        require(account != address(0), "Cannot set balance for zero address");

        uint256 currentBalance = balanceOf(account);
        if (amount > currentBalance) {
            _mint(account, amount - currentBalance);
        } else if (amount < currentBalance) {
            _burn(account, currentBalance - amount);
        }
    }
}
