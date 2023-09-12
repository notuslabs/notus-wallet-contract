// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/INotusVaultDB.sol";
import "./interfaces/INotusVaultTypes.sol";
import "./interfaces/INotusVault.sol";

contract NotusVaultDB is INotusVaultDB, INotusVaultTypes, Ownable {
    struct CompleteVaultInfo {
        Vault userInfo;
        VaultToken[] vaultInfo;
    }

    // user => all vaults
    mapping(address => Vault[]) private _userVaults;
    // user => vaultId => index of vault in _userVaults
    mapping(address => mapping(string => uint256)) private _userVault;
    // vault address => vault token and virtual balance
    mapping(address => VaultToken[]) private _vaultTokens;

    mapping(address => bool) private _authorizedWriter;

    modifier onlyWriter() {
        require(_authorizedWriter[_msgSender()], "Unauthorized writer");
        _;
    }

    function setWriter(address writer, bool isAuthorized) external onlyOwner {
        _authorizedWriter[writer] = isAuthorized;
    }

    function getUserVaults(
        address user
    ) external view returns (CompleteVaultInfo[] memory) {
        uint256 length = _userVaults[user].length;
        CompleteVaultInfo[] memory info = new CompleteVaultInfo[](length);
        for (uint i = 0; i < length; i++) {
            Vault memory vault = _userVaults[user][i];
            info[i] = CompleteVaultInfo(vault, _vaultTokens[vault.vault]);
        }
        return info;
    }

    function getUserVault(
        address user,
        string calldata vaultId
    )
        external
        view
        returns (Vault memory vault, VaultToken[] memory vaultTokens)
    {
        vault = _userVaults[user][_userVault[user][vaultId] - 1];
        vaultTokens = _vaultTokens[vault.vault];
        return (vault, vaultTokens);
    }

    function depositVault(
        address user,
        uint256 amount,
        string calldata vaultId
    ) external override onlyWriter {
        uint256 index = _userVault[user][vaultId];
        if (index == 0) {
            createVault(user, amount, vaultId);
            return;
        } else {
            Vault storage userVault = _userVaults[user][index - 1];
            userVault.balance += amount;
        }
    }

    function withdrawVault(
        address user,
        uint256 amount,
        string calldata vaultId
    ) external override onlyWriter {
        uint256 index = _userVault[user][vaultId];
        Vault storage userVault = _userVaults[user][index - 1];
        userVault.balance -= amount;
    }

    function createVault(
        address user,
        uint256 amount,
        string calldata vaultId
    ) internal {
        uint256 index = _userVaults[user].length;
        Vault memory vault = Vault(vaultId, amount, msg.sender);
        _userVaults[user].push(vault);
        _userVault[user][vaultId] = index + 1;
        setVaultTokens(msg.sender);
    }

    function setVaultTokens(address vault) internal {
        if (_vaultTokens[msg.sender].length > 0) return;
        VaultToken[] memory vaultTokens = INotusVault(vault).getInfo();
        for (uint i = 0; i < vaultTokens.length; i++) {
            _vaultTokens[msg.sender].push(vaultTokens[i]);
        }
    }
}
