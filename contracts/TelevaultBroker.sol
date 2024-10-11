// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Token
import { ITokenERC20 } from "@thirdweb-dev/contracts/prebuilts/interface/token/ITokenERC20.sol";
import { IERC1155 } from "@thirdweb-dev/contracts/eip/interface/IERC1155.sol";

// Receiver
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { ERC1155Holder, ERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

// Interface
import {IDirectListings} from "@thirdweb-dev/contracts/prebuilts/marketplace/IMarketplace.sol";

// Security + Utils
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";
import "@thirdweb-dev/contracts/lib/Strings.sol";

interface IEmblemvaultBellscoin {
    function setApprovalForAll(address, bool) external;
    function balanceOf(address, uint256) external view returns (uint256);
    function getOwnerOfSerial(uint256) external view returns (address);
    function getTokenIdForSerialNumber(uint256) external view returns (uint256);
}

interface ITelevaultExchange is IDirectListings {
    function createListing(ListingParameters memory) external returns (uint256);
}

contract TelevaultBroker is ERC1155Holder, ContractMetadata, PermissionsEnumerable {

    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public emblemvaultBELLS;
    address public televaultBELLS;
    address public televaultExchange;
    address public approvedAppraiser;
    bool public pausedStatus;

    event VaultListed(uint256 indexed listingId);
    event VTokenIssued(address indexed to, uint256 indexed vtokens);

    constructor(
        address _emblemvaultBELLS, 
        address _televaultBELLS, 
        address _televaultExchange,
        address _approvedAppraiser,
        address _initialAdmin
    ) {
        emblemvaultBELLS = _emblemvaultBELLS;
        televaultBELLS = _televaultBELLS;
        televaultExchange = _televaultExchange;
        approvedAppraiser = _approvedAppraiser;
        IEmblemvaultBellscoin(emblemvaultBELLS).setApprovalForAll(televaultExchange, true);

        _setupRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _setupRole(PAUSER_ROLE, _initialAdmin);
    }

    function televault(uint256 serialNumber, string memory assetId, 
    uint8 vAttestation, bytes32 rAttestation, bytes32 sAttestation,
    uint8 vAppraisal, bytes32 rAppraisal, bytes32 sAppraisal
    ) public  {
        address signerAttestation;
        address signerAppraisal;
        address tokenOwner;
        uint256 tokenId;
        string memory message;
        bytes32 expectedHash;

        require(pausedStatus == false, "contract is paused");

        //get the vault's owner address from the Emblem Vault contract
        tokenOwner = IEmblemvaultBellscoin(emblemvaultBELLS).getOwnerOfSerial(serialNumber);

        //get the vault's tokenId from the Emblem Vault contract
        tokenId = IEmblemvaultBellscoin(emblemvaultBELLS).getTokenIdForSerialNumber(serialNumber);
        
        require(msg.sender == tokenOwner, "Sender not token owner.");

        //reconstruct signed message using data from the Emblem Vault contract
        message = string(abi.encodePacked("{", Strings.toHexStringChecksummed(tokenOwner), ",",Strings.toString(serialNumber),",",Strings.toString(tokenId),",",assetId,"}")); 
            
        //recreate the message hash that was signed for the Attestation and Appraisal
        expectedHash = keccak256(abi.encodePacked(message));

        //retrieve the signer for the Attestation
        signerAttestation = verifyMessage(expectedHash, vAttestation, rAttestation, sAttestation);

        //retrieve the signer for the Appraisal
        signerAppraisal = verifyMessage(expectedHash, vAppraisal, rAppraisal, sAppraisal);

        require(signerAttestation == tokenOwner && signerAppraisal == approvedAppraiser, "signers do not match.");

        uint256 userBalanceBefore = IERC1155(emblemvaultBELLS).balanceOf(tokenOwner, tokenId);
        uint256 brokerBalanceBefore = IERC1155(emblemvaultBELLS).balanceOf(address(this), tokenId);

        //escrow the message sender's vault and transfer to this contract
        escrowVault(tokenId);

        uint256 userBalance = IERC1155(emblemvaultBELLS).balanceOf(tokenOwner, tokenId);
        uint256 brokerBalance = IERC1155(emblemvaultBELLS).balanceOf(address(this), tokenId);

        require(userBalance == userBalanceBefore - 1, 'user balance did not decrease.');
        require(brokerBalance == brokerBalanceBefore + 1, 'broker balance did not increase.');

        //issue tvToken to msg.msg.sender
        issueTokens(tokenId);

        //list vault on Televault Exchange
        listVault(tokenId);
        
    }

    function verifyMessage(bytes32 _hashedMessage, uint8 _v, bytes32 _r, bytes32 _s) private pure returns (address) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _hashedMessage));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer;
    }

    function escrowVault(uint256 _tokenId) private {
        //Calls Emblem Vault contract safeTransferFrom function to transfer vault from sender address to the contract
        IERC1155(emblemvaultBELLS).safeTransferFrom(msg.sender, address(this), _tokenId, 1, "");
    }

    function issueTokens(uint256 issueAmount) private {
        ITokenERC20(televaultBELLS).mintTo(msg.sender, (issueAmount * 10**18));
        emit VTokenIssued(msg.sender, issueAmount);
    }

    function listVault(uint256 _vaultId) private {
        uint128 _startTimestamp = uint128(block.timestamp + 1);
        uint128 _endTimestamp = uint128(_startTimestamp + 3155760000);

        IDirectListings.ListingParameters memory _params = IDirectListings.ListingParameters({
            assetContract: emblemvaultBELLS,
            tokenId: _vaultId,
            quantity: 1,
            currency: televaultBELLS,
            pricePerToken: uint256(_vaultId * 10**18),
            startTimestamp: _startTimestamp,
            endTimestamp: _endTimestamp,
            reserved: false
        });
        
        uint256 _listingId = ITelevaultExchange(televaultExchange).createListing(_params);
        emit VaultListed(_listingId);
    }

    function pauseBroker(bool _pauseStatus) external {
        require(hasRole(PAUSER_ROLE, msg.sender), "not pauser.");
        pausedStatus = _pauseStatus;
    }

    /// @dev Checks whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

}