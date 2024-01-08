// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Utils} from "./Utils.sol";

/// @title KryptoGame contract implementing an on-chain puzzle-solving game
/// @author M. Glinka
/// @notice This contract can be used to showcase a basic idea of Proof-of-Work and a simple Commit-Reveal scheme protecting against front-running
/// @custom:experimental The contract has not been audited and is provided as is only for demontrational and educational uses
contract KryptoGra is IERC165, IERC721Receiver {
    using SafeERC20 for IERC20;
    uint128 public constant COMMITMENT_TIME = 5 minutes; // time for a commiter to call the withdrawPuzzle function after commiting to a value
    uint256 public constant PUZZLE_SENDER_RECLAIM_TIME = 24 hours; // time after creation that need to pass for the puzzle creator to be able to reclaim the Puzzle

    struct Commitment {
        bytes32 answerHash; // keccak256 hash of the Puzzle's answer the claimer is commiting to
        uint256 producedAtBlock; // block number when the commitment was made
        uint256 validityDeadline; // timestamp until which the Commitment is valid
    }

    struct Puzzle {
        address senderAddress; // address of the sender
        uint256 timestamp; // timestamp of the puzzles
        bool isErc20; // true for ERC20, false for ERC721
        address tokenAddress; // address of the ERC smartcontract
        uint256 amount; // amount for ERC20 or 1 for ERC721
        uint256 tokenId; // ID for the ERC721 token
        uint8 difficulty; // number of zeros the keccak256(nonce concatened with tokenAddress) needs to start with
        bool claimed; // true if Puzzle was claimed, false otherwise
        address commitedTo; // address that was last to make a commitement to the Puzzle's solution
    }

    Puzzle[] public puzzles; // list of all Puzzles
    mapping(address => Commitment) private _commitments; // mapping from an address to a Commitment, max one Commitment per address

    // events
    event NewPuzzleEvent(
        uint256 indexed _index,
        bool indexed _isErc20,
        uint256 _amount,
        address indexed _senderAddress
    );
    event PuzzleClaimedEvent(
        uint256 indexed _index,
        bool indexed _isErc20,
        uint256 _amount,
        address indexed _recipientAddress
    );
    event MessageEvent(string message);

    // constructor
    constructor() {
        emit MessageEvent("Let's get ready to rumble!");
    }

    /**
     * @notice Implements the supportsInterface function
     * @dev ERC165 interface detection
     * @param _interfaceId bytes4 the interface identifier, as per ERC-165
     * @return bool true if the contract implements the _interfaceId interface
     */
    function supportsInterface(
        bytes4 _interfaceId
    ) external view override returns (bool) {
        return
            _interfaceId == type(IERC165).interfaceId ||
            _interfaceId == type(IERC721Receiver).interfaceId;
    }

    /**
     * @notice Create a Puzzle. Allowance must be set before calling this function
     * @param _tokenAddress address of the ERC smartcontract
     * @param _isErc20 bool true for ERC20, false for ERC721
     * @param _amount uint256 amount for ERC20 or 1 for ERC721
     * @param _tokenId uint256 ID for the ERC721 token
     * @param _difficulty uint256 Puzzle's difficulty, max 3
     * @return uint256 index of the Puzzle
     */
    function createPuzzle(
        bool _isErc20,
        address _tokenAddress,
        uint256 _amount,
        uint256 _tokenId,
        uint8 _difficulty
    ) public returns (uint256) {
        // Validate parameters
        require(
            _difficulty > 0 && _difficulty <= 3,
            "DIFFICULTY PARAM OUT OF RANGE (1,3)"
        );
        require(_amount >= 1, "MIN AMOUNT IS 1");
        // Handle the transfer to the KryptoGra contract depending on the type of the commited asset
        if (_isErc20) {
            IERC20 token = IERC20(_tokenAddress);

            token.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            IERC721 token = IERC721(_tokenAddress);

            token.safeTransferFrom(msg.sender, address(this), _tokenId, "");
        }

        // Create a new Puzzle
        puzzles.push(
            Puzzle({
                senderAddress: msg.sender,
                timestamp: block.timestamp,
                isErc20: _isErc20,
                tokenAddress: _tokenAddress,
                amount: _amount,
                tokenId: _tokenId,
                difficulty: _difficulty,
                claimed: false,
                commitedTo: address(0)
            })
        );

        // Emit the NewPuzzleEvents
        emit NewPuzzleEvent(puzzles.length - 1, _isErc20, _amount, msg.sender);

        // Return the Puzzle index
        return puzzles.length - 1;
    }

    /**
     * @notice ERC721 token receiver function
     * @dev These functions are called by the token contracts when a token is sent to this contract. We only accept token transfers requested by our smartcontract.
     * @param _operator address operator requesting the transfer
     * @param _from address address which previously owned the token
     * @param _tokenId uint256 ID of the token being transferred
     * @param _data bytes data to send along with a safe transfer check (has to be 32 bytes)
     */
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        if (_operator == address(this)) {
            // If operator is this contract, nothing to do, return
            return this.onERC721Received.selector;
        } else {
            // If tokens sent by another party, revert
            revert(
                "ONLY TOKEN TRANSFERS REQUESTED BY THIS GAME CONTRACT ARE SUPPORTED"
            );
        }
    }

    /**
     * @notice Commit to an answer hash
     * @dev Only once commitment per address is permitted. If new commitment from an address sent, the old commitment will be overriden
     * @param _index uint256 ID of the Puzzle the Commitment refers to
     * @param _commitedHash bytes32 hash the sender commit to
     * @return bool true if successful
     */
    function commitToHash(
        uint256 _index,
        bytes32 _commitedHash
    ) public returns (bool) {
        // check that the Puzzle exists and that it isn't already withdrawn
        require(_index < puzzles.length, "PUZZLE INDEX DOES NOT EXIST");
        Puzzle storage _puzzle = puzzles[_index];
        require(_puzzle.claimed == false, "PUZZLE ALREADY WITHDRAWN");
        // check that Puzzle is not locked with a valid commitment
        require(
            _commitments[_puzzle.commitedTo].validityDeadline < block.timestamp,
            "PUZZLE LOCKED"
        );
        // check that the commitedHash satisfies the difficulty contraint of the puzzle
        string memory commiteHashStr = Utils.toHex(_commitedHash);
        for (uint256 i = 2; i < 2 + _puzzle.difficulty; i++) {
            require(
                Strings.equal(Utils.substring(commiteHashStr, i, i + 1), "0"),
                "DIFFICULTY NOT SATISFIED"
            );
        }
        _commitments[msg.sender] = Commitment({
            answerHash: _commitedHash,
            producedAtBlock: block.number,
            validityDeadline: block.timestamp + COMMITMENT_TIME
        });

        _puzzle.commitedTo = msg.sender;

        return true;
    }

    /**
     * @notice Function to withdraw a Puzzle to the recipient address.
     * @param _index uint256 index of the Puzzle
     * @param _guessedNonce uint256 noce that once concatenated and hashed with puzzle-reward-token address produces the desired answer
     * @return bool true if successful
     */
    function withdrawPuzzle(
        uint256 _index,
        uint256 _guessedNonce
    ) external returns (bool) {
        // check that the Puzzle exists and that it isn't already withdrawn
        require(_index < puzzles.length, "PUZZLE INDEX DOES NOT EXIST");
        Puzzle memory _puzzle = puzzles[_index];
        require(_puzzle.claimed == false, "PUZZLE ALREADY WITHDRAWN");
        // check if commitment exists and did not expire
        require(
            _commitments[msg.sender].validityDeadline >= block.timestamp,
            "COMMITMENT EXPIRED OR NONEXISTANT"
        );
        require(
            _commitments[msg.sender].producedAtBlock < block.number,
            "CANNOT REVEAL IN THE SAME BLOCK"
        );
        _checkCommitment(
            _commitments[msg.sender].answerHash,
            _guessedNonce,
            _puzzle.tokenAddress
        );

        // emit the withdraw event
        emit PuzzleClaimedEvent(
            _index,
            _puzzle.isErc20,
            _puzzle.amount,
            msg.sender
        );

        // mark as claimed
        puzzles[_index].claimed = true;

        // Puzzle request is valid. Withdraw the Puzzle to the recipient address.
        if (_puzzle.isErc20) {
            /// handle ERC20 puzzles
            IERC20 token = IERC20(_puzzle.tokenAddress);
            token.safeTransfer(msg.sender, _puzzle.amount);
        } else {
            /// handle ERC721 puzzles
            IERC721 token = IERC721(_puzzle.tokenAddress);
            token.safeTransferFrom(address(this), msg.sender, _puzzle.tokenId);
        }

        return true;
    }

    /**
     * @notice Function to allow a sender to withdraw their Puzzle after PUZZLE_SENDER_RECLAIM_TIME passed
     * @param _index uint256 index of the Puzzle
     * @return bool true if successful
     */
    function withdrawPuzzleSender(uint256 _index) external returns (bool) {
        // check that the Puzzle exists and that it isn't already withdrawn
        require(_index < puzzles.length, "PUZZLE INDEX DOES NOT EXIST");
        Puzzle memory _puzzle = puzzles[_index];
        require(_puzzle.claimed == false, "PUZZLE ALREADY WITHDRAWN");
        // check that the sender is the one who made the Puzzle
        require(_puzzle.senderAddress == msg.sender, "NOT THE CREATOR");
        // check that PUZZLE_SENDER_RECLAIM_TIME has passed since the Puzzle was created
        require(
            block.timestamp >= _puzzle.timestamp + PUZZLE_SENDER_RECLAIM_TIME,
            "PUZZLE_SENDER_RECLAIM_TIME NOT REACHED YET"
        );

        // emit the withdraw event
        emit PuzzleClaimedEvent(
            _index,
            _puzzle.isErc20,
            _puzzle.amount,
            _puzzle.senderAddress
        );

        // Delete the Puzzle
        puzzles[_index].claimed = true;

        if (_puzzle.isErc20) {
            /// handle ERC20 puzzles
            IERC20 token = IERC20(_puzzle.tokenAddress);
            token.safeTransfer(_puzzle.senderAddress, _puzzle.amount);
        } else {
            /// handle ERC721 puzzles
            IERC721 token = IERC721(_puzzle.tokenAddress);
            token.safeTransferFrom(
                address(this),
                _puzzle.senderAddress,
                _puzzle.tokenId
            );
        }

        return true;
    }

    //// Helper definitions ////
    function computeHash(
        uint256 _guessedNonce,
        address _tokenAddress
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    Strings.toString(_guessedNonce),
                    Strings.toHexString(_tokenAddress)
                )
            );
    }

    /**
     * @notice Function to check if commited hash is equal to the computed hash from the sent answer
     * @param _commitedHash bytes32 the commited hash to which the computed hash is compared
     * @param _guessedNonce uint256 nonce used to compute the hash
     * @param _tokenAddress address token-smartcontract address used to compute the hash
     * @return bool true if successful
     */
    function _checkCommitment(
        bytes32 _commitedHash,
        uint256 _guessedNonce,
        address _tokenAddress
    ) private pure returns (bool) {
        bytes32 computedHash = computeHash(_guessedNonce, _tokenAddress);
        require(computedHash == _commitedHash, "HASHES NOT EQUAL");

        return true;
    }

    /**
     * @notice Simple way to get the total number of puzzles
     * @return uint256 number of puzzles
     */
    function getPuzzleCount() external view returns (uint256) {
        return puzzles.length;
    }

    /**
     * @notice Simple way to get single Puzzle
     * @param _index uint256 index of the Puzzle
     * @return Puzzle puzzle details
     * }
     */
    function getPuzzle(uint256 _index) external view returns (Puzzle memory) {
        return puzzles[_index];
    }

    /**
     * @notice Get all puzzles in contract
     * @return Puzzle[] array of puzzles
     */
    function getAllPuzzles() external view returns (Puzzle[] memory) {
        return puzzles;
    }

    /**
     * @notice Get all puzzles for a given address
     * @param _address address of the puzzles
     * @return Puzzle[] array of puzzles
     */
    function getAllPuzzlesForAddress(
        address _address
    ) external view returns (Puzzle[] memory) {
        Puzzle[] memory _puzzles = new Puzzle[](puzzles.length);
        uint256 count = 0;
        for (uint256 i = 0; i < puzzles.length; i++) {
            if (puzzles[i].senderAddress == _address) {
                _puzzles[count] = puzzles[i];
                count++;
            }
        }
        return _puzzles;
    }
}
