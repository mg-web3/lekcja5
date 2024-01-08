// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract ERC721Mock is ERC721Enumerable {
    constructor() ERC721("ERC721Mock", "M721") {
        this;
    }

    // mint function mints tokens to the specified address
    function mint(address account, uint256 id) external {
        _mint(account, id);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public pure override(ERC721, IERC721) {
        revert("USE SAFETRANSFERFROM");
    }
}
