// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {KryptoGra} from "../src/KryptoGra.sol";
import {Utils} from "../src/Utils.sol";
import {ERC20Mock} from "./MockErc20.sol";
import {ERC721Mock} from "./MockErc721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract KryptoGraTest is Test {
    KryptoGra public game;
    ERC20Mock public erc20;
    ERC721Mock public erc721;
    address public bob = address(1);
    address public alice = address(2);
    address public john = address(3);

    function setUp() public {
        game = new KryptoGra();
        erc20 = new ERC20Mock();
        erc721 = new ERC721Mock();
    }

    function mintMockErc(
        address _to,
        bool _isErc20,
        uint256 _amount,
        bool autoApprove
    ) public {
        vm.startPrank(_to);
        if (_isErc20) {
            erc20.mint(_to, _amount);
            if (autoApprove) {
                erc20.approve(address(game), _amount);
            }
        } else {
            for (uint i = 0; i < _amount; i++) {
                uint tokenId = erc721.totalSupply() + 1;
                erc721.mint(_to, tokenId);
                if (autoApprove) {
                    erc721.approve(address(game), tokenId);
                }
            }
        }
        vm.stopPrank();
    }

    function solvePuzzle(uint256 _index) public view returns (uint256) {
        KryptoGra.Puzzle memory puzz = game.getPuzzle(_index);
        bytes32 computedHash = "1234567890";
        uint nonce = 0;
        string memory difString = "";

        for (uint i = 0; i < puzz.difficulty; i++) {
            difString = string.concat(difString, "0");
        }

        while (
            !Strings.equal(
                Utils.substring(
                    Utils.toHex(computedHash),
                    2,
                    puzz.difficulty + 2
                ),
                difString
            )
        ) {
            nonce++;
            computedHash = game.computeHash(nonce, address(puzz.tokenAddress));
        }

        return nonce;
    }

    function testPuzzleListInitiallyEmpty() public {
        assertEq(0, game.getAllPuzzles().length);
        assertEq(0, game.getPuzzleCount());
    }

    function testCreateOneErc20Puzzle() public {
        mintMockErc(bob, true, 10, true);
        assertEq(10, erc20.balanceOf(bob));

        vm.startPrank(bob);
        game.createPuzzle(true, address(erc20), 4, 0, 1);

        assertEq(1, game.getPuzzleCount());
        assertEq(4, game.getPuzzle(0).amount);
        assertEq(6, erc20.balanceOf(bob));
        assertEq(4, erc20.balanceOf(address(game)));
    }

    function testCreateOneErc721Puzzle() public {
        mintMockErc(bob, false, 1, true);
        assertEq(1, erc721.balanceOf(bob));

        vm.startPrank(bob);
        game.createPuzzle(false, address(erc721), 1, 1, 1);

        assertEq(1, game.getPuzzleCount());
        assertEq(1, game.getPuzzle(0).amount);
        assertEq(0, erc721.balanceOf(bob));
        assertEq(1, erc721.balanceOf(address(game)));
    }

    function testCreateAndClaimBackOneErc20Puzzle() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);
        vm.warp(block.timestamp + 25 hours);
        game.withdrawPuzzleSender(index);
    }

    function testCreateAndClaimBackTooSoon() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert();
        game.withdrawPuzzleSender(index);
    }

    function testSolveOneErc20Puzzle() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);

        vm.startPrank(alice);
        uint256 nonce = solvePuzzle(index);
        game.commitToHash(index, game.computeHash(nonce, address(erc20)));
        vm.roll(block.number + 1);
        game.withdrawPuzzle(index, nonce);
    }

    function testSolveOneErc20PuzzleWithDoubleCommit() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);

        vm.startPrank(alice);
        game.commitToHash(
            index,
            bytes32(
                0x077BDE88A205482D5417952E732D70802B952A0F36E7774A879A4C7939F00E8D
            )
        );
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10 minutes);
        vm.expectRevert();
        game.withdrawPuzzle(index, 1);
        uint256 nonce = solvePuzzle(index);
        game.commitToHash(index, game.computeHash(nonce, address(erc20)));
        vm.roll(block.number + 1);
        game.withdrawPuzzle(index, nonce);
    }

    function testFailSolveOneErc20PuzzleButNoCommit() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);

        vm.startPrank(alice);
        uint256 nonce = solvePuzzle(index);
        game.withdrawPuzzle(index, nonce);
    }

    function testFailToSolveOneErc20Puzzle() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);

        vm.startPrank(alice);
        uint256 nonce = 1;
        game.commitToHash(index, game.computeHash(nonce, address(erc20)));
        vm.roll(block.number + 1);
        game.withdrawPuzzle(index, nonce);
    }

    function testFailToClaimAfterCommittmentExpired() public {
        mintMockErc(bob, true, 10, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(true, address(erc20), 4, 0, 1);

        vm.startPrank(alice);
        uint256 nonce = solvePuzzle(index);
        game.commitToHash(index, game.computeHash(nonce, address(erc20)));
        vm.warp(block.timestamp + 10 minutes);
        vm.roll(block.number + 1);
        game.withdrawPuzzle(index, nonce);
    }

    function testSolveOneErc721Puzzle() public {
        mintMockErc(bob, false, 1, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(false, address(erc721), 1, 1, 2);

        vm.startPrank(alice);
        uint256 nonce = solvePuzzle(index);
        game.commitToHash(index, game.computeHash(nonce, address(erc721)));
        vm.roll(block.number + 1);
        game.withdrawPuzzle(index, nonce);
    }

    function testFrontrunAttempt() public {
        mintMockErc(bob, false, 1, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(false, address(erc721), 1, 1, 2);

        vm.startPrank(alice);
        uint256 nonce = solvePuzzle(index);
        bytes32 hashToCommit = game.computeHash(nonce, address(erc721));
        game.commitToHash(index, hashToCommit);
        vm.roll(block.number + 1);

        vm.startPrank(john);
        vm.expectRevert();
        game.commitToHash(index, hashToCommit);
        vm.expectRevert();
        game.withdrawPuzzle(index, nonce);

        vm.startPrank(alice);
        game.withdrawPuzzle(index, nonce);
    }

    function testFailCommitToACommitedPuzzle() public {
        mintMockErc(bob, false, 1, true);

        vm.startPrank(bob);
        uint index = game.createPuzzle(false, address(erc721), 1, 1, 2);

        vm.startPrank(alice);
        uint256 nonce = solvePuzzle(index);
        game.commitToHash(index, game.computeHash(nonce, address(erc721)));

        vm.startPrank(john);
        game.commitToHash(index, game.computeHash(nonce, address(erc721)));
    }

    function testSolveMultiPuzzles() public {
        uint numMints = 1 + (uint(vm.unixTime()) % uint(10));
        for (uint i = 0; i < numMints; i++) {
            uint randomNum = 1 + (uint(vm.unixTime()) % uint(10));
            vm.sleep(1000);
            address creator = randomNum <= 5 ? bob : alice;
            bool isErc20 = randomNum <= 5 ? true : false;
            uint amount = randomNum <= 5 ? randomNum : 1;
            mintMockErc(creator, isErc20, amount, true);

            vm.startPrank(creator);
            game.createPuzzle(
                isErc20,
                isErc20 ? address(erc20) : address(erc721),
                amount > 1 ? amount - 1 : amount,
                isErc20 ? 0 : erc721.totalSupply(),
                isErc20 ? 2 : 3
            );
        }

        vm.startPrank(john);
        for (uint i = 0; i < numMints; i++) {
            KryptoGra.Puzzle memory puzz = game.getPuzzle(i);
            uint nonce = solvePuzzle(i);
            game.commitToHash(
                i,
                game.computeHash(
                    nonce,
                    puzz.isErc20 ? address(erc20) : address(erc721)
                )
            );
            vm.roll(block.number + 1);
            game.withdrawPuzzle(i, nonce);
        }
        vm.stopPrank();
    }
}
