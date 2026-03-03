// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Permit2Payments} from "../../Permit2Payments.sol";
import {V4Router} from "v4-periphery/src/V4Router.sol";
import {IVault} from "v4-core/src/interfaces/IVault.sol";
import {ICLPoolManager} from "v4-core/src/interfaces/ICLPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @title Router for SunSwap V4 Trades
abstract contract V4SwapRouter is V4Router, Permit2Payments {
    constructor(address _vault, address _clPoolManager)
        V4Router(IVault(_vault), ICLPoolManager(_clPoolManager))
    {}

    function _pay(Currency token, address payer, uint256 amount) internal override {
        payOrPermit2Transfer(Currency.unwrap(token), payer, address(vault), amount);
    }
}
