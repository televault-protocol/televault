// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

// Tokens
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Security
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

// Utils
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";

/**
 * @author  @GrahamBellscoin
 */
contract VaultedToken is
    ERC20,
    ReentrancyGuard,
    PermissionsEnumerable,
    ContractMetadata
{
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

    address public televaultBroker;

    event TokensIssued(address toAddress, uint256 tokensIssuedAmount);
    event TokensBurned(uint256 tokensBurnedAmount);
    event BrokerAddressSet(address brokerAddress);

    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        // Set initial roles for deployer
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, address(0));
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        super._afterTokenTransfer(from, to, amount);
        if (to == televaultBroker) {
          emit TokensBurned(amount); 
          _burn(televaultBroker, amount);
        }
    }

    /// @dev Runs on every transfer.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            require(hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to), "transfers restricted.");
        }
    }

    function _mint(address account, uint256 amount) internal virtual override(ERC20) {
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override(ERC20) {
        super._burn(account, amount);
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mintTo(address to, uint256 amount) public virtual nonReentrant {
        require(hasRole(MINTER_ROLE, _msgSender()), "not minter.");
        emit TokensIssued(to, amount);
        _mintTo(to, amount);
    }

    /// @dev Mints `amount` of tokens to `to`
    function _mintTo(address _to, uint256 _amount) internal {
        _mint(_to, _amount);
    }

    /// @dev Sets the Televault Broker address `_brokerAddress`
    function setBroker(address _brokerAddress) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "not admin.");
        televaultBroker = _brokerAddress;
        _setupRole(MINTER_ROLE, televaultBroker);
        emit BrokerAddressSet(televaultBroker);
    }

    /// @dev Checks whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
}