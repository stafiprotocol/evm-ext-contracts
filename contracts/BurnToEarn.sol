// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./base/Ownable.sol";

contract BurnToEarn is Initializable, UUPSUpgradeable, Ownable {
    using SafeERC20 for IERC20;

    error BurnAmountTooLow();
    error ActEnd();

    event Burn(address user, uint256 amount, uint8 projectId, string recipient);
    event Withdraw(uint256 amount, address recipient);

    address public tokenAddress;
    uint256 public minAmount;
    mapping(uint8 => uint256) public endTime;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        uint256 _minAmount,
        uint8 _projectId,
        uint256 _endTime
    ) external initializer {
        _initOwner(msg.sender);

        tokenAddress = _tokenAddress;
        minAmount = _minAmount;

        endTime[_projectId] = _endTime;
    }

    // getter

    function version() external view returns (uint8) {
        return _getInitializedVersion();
    }

    // owner

    function _authorizeUpgrade(
        address _newImplementation
    ) internal override onlyOwner {}

    function updateMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
    }

    function updateEndTime(
        uint8 _projectId,
        uint256 _endTime
    ) external onlyOwner {
        endTime[_projectId] = _endTime;
    }

    function withdraw(address _recipient) external onlyOwner {
        uint256 amount = IERC20(tokenAddress).balanceOf(address(this));
        if (amount > 0) {
            IERC20(tokenAddress).safeTransfer(_recipient, amount);

            emit Withdraw(amount, _recipient);
        }
    }

    // user

    function burn(
        uint256 _amount,
        uint8 _projectId,
        string calldata _recipient
    ) external {
        if (_amount < minAmount) revert BurnAmountTooLow();
        if (block.timestamp > endTime[_projectId]) revert ActEnd();

        // transfer erc20 token
        IERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        emit Burn(msg.sender, _amount, _projectId, _recipient);
    }
}
