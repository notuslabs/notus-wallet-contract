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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/INotusVault.sol";
import "./interfaces/INotusVaultDB.sol";
import "./interfaces/INotusVaultTypes.sol";

contract NotusSwapVault is INotusVaultTypes, Ownable {
    using SafeERC20 for IERC20;

    struct JoinParams {
        IERC20 tokenIn;
        uint256 amountIn;
        address vault;
        uint256 minAmountOut;
        string vaultId;
        bytes[] datas;
    }

    address private _swapProvider;
    address private _proxyTransfer;
    address private _dbContract;
    address private _notus;

    constructor(
        address swapProvider,
        address proxyTransfer,
        address dbContract,
        address notus
    ) {
        _swapProvider = swapProvider;
        _proxyTransfer = proxyTransfer;
        _dbContract = dbContract;
        _notus = notus;
    }

    function updateSwapProvider(
        address newSwapProvider,
        address newProxyTransfer
    ) external onlyOwner {
        _swapProvider = newSwapProvider;
        _proxyTransfer = newProxyTransfer;
    }

    function updateDbContract(address newDbContract) external onlyOwner {
        _dbContract = newDbContract;
    }

    function withdrawTokens(
        IERC20[] calldata tokens,
        address to
    ) external onlyOwner {
        uint256 length = tokens.length;
        for (uint i = 0; i < length; i++) {
            tokens[i].safeTransfer(to, tokens[i].balanceOf(address(this)));
        }
    }

    function join(
        JoinParams calldata params
    )
        external
        returns (VaultToken[] memory tokensAndAmounts, uint256 amountOut)
    {
        VaultToken[] memory tokensVault = INotusVault(params.vault).getInfo();

        params.tokenIn.safeTransferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        _approve(params.tokenIn, _proxyTransfer, params.amountIn);

        _callSwapProvider(params.datas);

        address tokenInVault;
        uint256 amountInvault;
        uint256 compareVirtual = type(uint256).max;
        uint256 length = tokensVault.length;
        for (uint i = 0; i < length; i++) {
            VaultToken memory tokenVault = tokensVault[i];
            uint256 amount = IERC20(tokenVault.token).balanceOf(address(this));
            // 45623874741823682 - (45623874741823682 % 17) = 45623874741823682
            uint256 virtualAmount = _calcAmountOut(
                amount,
                tokenVault.virtualAmount
            );

            if (virtualAmount < compareVirtual) {
                compareVirtual = virtualAmount;
                amountInvault = amount;
                tokenInVault = tokenVault.token;
            }

            _approve(IERC20(tokenVault.token), params.vault, amount);
        }

        (tokensAndAmounts, amountOut) = INotusVault(params.vault)
            .depositExactAmountIn(
                tokenInVault,
                amountInvault,
                msg.sender
            );

        require(
            amountOut >= params.minAmountOut,
            "Amount out is less than the min"
        );

        INotusVaultDB(_dbContract).depositVault(msg.sender, amountOut, params.amountIn, params.vault, params.vaultId);

        _withdrawFee(tokensVault);

        params.tokenIn.safeTransfer(
            _notus,
            params.tokenIn.balanceOf(address(this))
        );
    }

    function exit(
        address vault,
        uint256 amountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        string calldata vaultId,
        bytes[] calldata datas
    ) external returns (VaultToken[] memory tokensOutVault, uint256 amountOut) {
        IERC20(vault).safeTransferFrom(msg.sender, address(this), amountIn);

        VaultToken[] memory tokensVault = INotusVault(vault).getInfo();

        tokensOutVault = INotusVault(vault).withdraw(
            amountIn,
            address(this)
        );

        uint256 length = tokensVault.length;
        for (uint i = 0; i < length; i++) {
            IERC20 token = IERC20(tokensVault[i].token);
            _approve(token, _proxyTransfer, token.balanceOf(address(this)));
        }

        _callSwapProvider(datas);

        amountOut = tokenOut.balanceOf(address(this));
        require(amountOut >= minAmountOut);

        INotusVaultDB(_dbContract).withdrawVault(msg.sender, amountIn, amountOut, vaultId);

        tokenOut.safeTransfer(msg.sender, amountOut);

        _withdrawFee(tokensVault);
    }

    function _approve(IERC20 token, address to, uint256 amount) internal {
        if (token.allowance(address(this), to) < amount) {
            token.safeApprove(to, type(uint256).max);
        }
    }

    function _callSwapProvider(bytes[] calldata datas) internal {
        uint256 length = datas.length;
        for (uint i = 0; i < length; i++) {
            (bool success, ) = _swapProvider.call{value: 0}(datas[i]);
            require(success, "Error swap");
        }
    }

    function _getTokensInBalance(
        VaultToken[] memory tokensIn
    ) internal view returns (uint256[] memory) {
        uint256 length = tokensIn.length;
        uint256[] memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = IERC20(tokensIn[i].token).balanceOf(address(this));
        }

        return balances;
    }

    function _withdrawFee(VaultToken[] memory tokensVault) private {
        uint256 length = tokensVault.length;
        for (uint i = 0; i < length; i++) {
            IERC20 token = IERC20(tokensVault[i].token);
            token.safeTransfer(_notus, token.balanceOf(address(this)));
        }
    }

    function _calcAmountOut(
        uint256 amount,
        uint256 virtualBalance
    ) internal pure returns (uint256) {
        return (amount * 1e18) / virtualBalance;
        // 45623874741823682 - (45623874741823682 % 17) / 17 = 2683757337754334
    }
}
