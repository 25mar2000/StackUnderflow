// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "main.sol";

contract TestContract is Ownable{
    event Print(string message);

    function getBalance() external view returns (uint balance){
        return address(this).balance;
    }
}