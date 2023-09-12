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

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/INotusVault.sol";
import "./interfaces/INotusVaultDB.sol";

contract NotusVault is INotusVault, INotusVaultTypes, ERC20, Ownable {
    using SafeERC20 for IERC20;

    uint256 constant ONE = 1e18;

    mapping(address => uint256) private _getVirtualAmount;

    VaultToken[] private _info;
    address private _notusSwap;

    constructor(
        address[] memory tokens,
        uint256[] memory virtualAmount,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        uint256 _length = tokens.length;
        require(
            _length > 0 && _length == virtualAmount.length,
            "Mismatch length"
        );

        for (uint i = 0; i < _length; i++) {
            require(
                virtualAmount[i] > 0,
                "Virtual amount must be greater than 0"
            );
            require(
                tokens[i] != address(0),
                "Token must be different from address zero"
            );
            _info.push(VaultToken(tokens[i], virtualAmount[i]));
            _getVirtualAmount[tokens[i]] = virtualAmount[i];
        }
    }

    modifier onlyNotusSwap() {
        require(msg.sender == _notusSwap, "Caller is not NotusSwap");
        _;
    }

    function getInfo() external view override returns (VaultToken[] memory) {
        return _info;
    }

    function updateNotusSwap(address notusSwap) external onlyOwner {
        _notusSwap = notusSwap;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override onlyNotusSwap returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override onlyNotusSwap returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function depositExactAmountOut(
        uint256 amountOut,
        address recipient,
        address dbContract,
        string calldata vaultId
    ) external onlyNotusSwap returns (VaultToken[] memory) {
        require(amountOut > 0, "Amount must be greater than 0");

        uint256 _length = _info.length;
        VaultToken[] memory tokensIn = new VaultToken[](_length);
        for (uint i = 0; i < _length; i++) {
            address token = _info[i].token;
            uint256 virtualAmount = _info[i].virtualAmount;
            uint256 amountIn = (virtualAmount * amountOut) / ONE;

            tokensIn[i] = (VaultToken(token, amountIn));

            IERC20(token).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        _mint(recipient, amountOut);

        INotusVaultDB(dbContract).depositVault(recipient, amountOut, vaultId);

        return tokensIn;
    }

    function depositExactAmountIn(
        address tokenIn,
        uint256 amountIn,
        address recipient,
        address dbContract,
        string calldata vaultId
    ) external override onlyNotusSwap returns (VaultToken[] memory, uint256) {
        uint256 amountOut = (amountIn * ONE) / _safeVirtualAmount(tokenIn);
        require(amountOut > 0, "Invalid amount IN");
        uint256 _length = _info.length;
        VaultToken[] memory tokensIn = new VaultToken[](_length);
        for (uint i = 0; i < _length; i++) {
            address token = _info[i].token;
            uint256 virtualAmount = _info[i].virtualAmount;
            uint256 _amountIn = (virtualAmount * amountOut) / ONE;

            tokensIn[i] = VaultToken(token, _amountIn);

            IERC20(token).safeTransferFrom(
                msg.sender,
                address(this),
                _amountIn
            );
        }

        _mint(recipient, amountOut);

        INotusVaultDB(dbContract).depositVault(recipient, amountOut, vaultId);

        return (tokensIn, amountOut);
    }

    function withdraw(
        uint256 amountIn,
        address user,
        address recipient,
        address dbContract,
        string calldata vaultId
    ) external override onlyNotusSwap returns (VaultToken[] memory) {
        _burn(msg.sender, amountIn);

        INotusVaultDB(dbContract).withdrawVault(user, amountIn, vaultId);

        uint256 _length = _info.length;
        VaultToken[] memory tokensOut = new VaultToken[](_length);
        for (uint i = 0; i < _length; i++) {
            address token = _info[i].token;
            uint256 virtualAmount = _info[i].virtualAmount;
            uint256 amountOut = (virtualAmount * amountIn) / ONE;

            tokensOut[i] = (VaultToken(token, amountOut));

            IERC20(token).safeTransfer(recipient, amountOut);
        }

        return tokensOut;
    }

    function calcWithdrawAmountsOut(
        uint256 amountIn
    ) external view returns (VaultToken[] memory) {
        uint256 _length = _info.length;
        VaultToken[] memory tokensOut = new VaultToken[](_length);
        for (uint i = 0; i < _length; i++) {
            address token = _info[i].token;
            uint256 virtualAmount = _info[i].virtualAmount;
            uint256 amountOut = (virtualAmount * amountIn) / ONE;

            tokensOut[i] = (VaultToken(token, amountOut));
        }

        return tokensOut;
    }

    function _safeVirtualAmount(address token) internal view returns (uint256) {
        uint256 virtualAmount = _getVirtualAmount[token];
        require(virtualAmount > 0, "Invalid Token In");

        return virtualAmount;
    }
}
