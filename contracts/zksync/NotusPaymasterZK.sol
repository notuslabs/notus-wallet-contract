import {IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {TransactionHelper, Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NotusPaymasterZK is IPaymaster, Ownable {
    using SafeERC20 for IERC20;

    uint256 private _priceForPayingFees;

    IERC20 public allowedToken;
    address public allowedFactory;

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        _;
    }

    constructor(IERC20 _allowedToken, address _allowedFactory) {
        allowedToken = _allowedToken;
        allowedFactory = _allowedFactory;
        _priceForPayingFees = 1e18;
    }

    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    )
        external
        payable
        onlyBootloader
        returns (bytes4 magic, bytes memory context)
    {
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

        if (address(uint160(_transaction.to)) == allowedFactory) {
            _payBootloader(requiredETH);
            return (magic, context);
        }

        require(
            _transaction.paymasterInput.length >= 4,
            "The standard paymaster input must be at least 4 bytes long"
        );

        bytes4 paymasterInputSelector = bytes4(
            _transaction.paymasterInput[0:4]
        );
        if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
            (address token, uint256 amount, ) = abi.decode(
                _transaction.paymasterInput[4:],
                (address, uint256, bytes)
            );

            require(IERC20(token) == allowedToken, "Invalid token");

            address userAddress = address(uint160(_transaction.from));

            address thisAddress = address(this);

            uint256 providedAllowance = IERC20(token).allowance(
                userAddress,
                thisAddress
            );

            require(
                providedAllowance >= _priceForPayingFees,
                "Min allowance too low"
            );

            try
                IERC20(allowedToken).transferFrom(
                    userAddress,
                    thisAddress,
                    amount
                )
            {} catch (bytes memory revertReason) {
                if (revertReason.length <= 4) {
                    revert("Failed to transferFrom from users' account");
                } else {
                    assembly {
                        revert(add(0x20, revertReason), mload(revertReason))
                    }
                }
            }

            _payBootloader(requiredETH);
        } else {
            revert("Unsupported paymaster flow");
        }
    }

    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32,
        bytes32,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable override onlyBootloader {}

    function withdrawFunds() external payable onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}(
            ""
        );
        require(success, "Failed withdraw funds");
    }

    function withdrawToken(uint256 amount) external payable onlyOwner {
        allowedToken.transfer(owner(), amount);
    }

    function getFee() external view returns (address token, uint256 priceFee) {
        return (address(allowedToken), _priceForPayingFees);
    }

    function updateFee(uint256 newPriceFee) external onlyOwner {
        _priceForPayingFees = newPriceFee;
    }

    function updateAllowedFactory(address newAllowedFactory) external onlyOwner {
        allowedFactory = newAllowedFactory;
    }

    function _payBootloader(uint256 requiredETH) private {
        (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
            value: requiredETH
        }("");

        require(
            success,
            "Failed to transfer tx fee to the bootloader. Paymaster balance might not be enough."
        );
    }

    receive() external payable {}
}
