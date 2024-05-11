// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

library LibAddressSet {
    struct AddressSet {
        address[] actors;
        mapping(address => bool) isSaved;
    }

    function add(AddressSet storage set, address actor) internal {
        if (!set.isSaved[actor]) {
            set.actors.push(actor);
            set.isSaved[actor] = true;
        }
    }

    function rand(AddressSet storage set, uint256 seed) internal view returns (address) {
        if (set.actors.length > 0) {
            uint256 index = seed % set.actors.length;
            return set.actors[index];
        }
        return address(0);
    }

    function forEach(AddressSet storage set, function(address) external view func) internal view {
        for (uint256 i; i < set.actors.length; i++) {
            func(set.actors[i]);
        }
    }

    function reduce(
        AddressSet storage set,
        uint256 accumulator,
        function(uint256,address) external view returns (uint256) func
    ) internal view returns (uint256) {
        for (uint256 i; i < set.actors.length; i++) {
            accumulator = func(accumulator, set.actors[i]);
        }

        return accumulator;
    }
}
