// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

/// @notice The one Halmos cheatcode these checks use, declared here instead of adding the halmos-cheatcodes
///         package. Halmos intercepts calls to SVM_ADDRESS; under forge the address has no code, and no
///         `check_` function is run by forge.
/// @dev SVM_ADDRESS = address(uint160(uint256(keccak256("svm cheat code")))), as in halmos-cheatcodes.
interface SVM {
    /// @notice Calldata for any external function of `contractName`, with symbolic arguments.
    function createCalldata(string calldata contractName) external pure returns (bytes memory data);
}

address constant SVM_ADDRESS = address(uint160(uint256(keccak256("svm cheat code"))));
