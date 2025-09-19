// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract SmartRoyalty is Ownable, ReentrancyGuard {
    uint256 public constant BASIS_POINTS = 10_000;

    struct Royalty {
        address recipient;
        uint96 share; 
    }

    // contentId => array of royalty splits
    mapping(uint256 => Royalty[]) private royalties;

    // recipient => owed amount (pull payments)
    mapping(address => uint256) public pendingWithdrawals;

    event RoyaltiesSet(uint256 indexed contentId);
    event RoyaltiesFunded(uint256 indexed contentId, uint256 totalAmount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event RecipientUpdated(uint256 indexed contentId, address indexed oldRecipient, address indexed newRecipient);

    modifier validInput(address[] calldata recipients, uint256[] calldata shares) {
        uint256 len = recipients.length;
        require(len > 0 && len == shares.length, "Invalid input");
        _;
    }

    /**
     * @notice Configure royalty recipients for a contentId.
     * @dev Only owner can call.
     */

    function setRoyalties(
        uint256 contentId,
        address[] calldata recipients,
        uint256[] calldata shares
    ) external onlyOwner validInput(recipients, shares) {
        delete royalties[contentId];
        Royalty[] storage list = royalties[contentId];

        uint256 total;
        uint256 len = recipients.length;
        for (uint256 i; i < len; ) {
            address r = recipients[i];
            uint256 s = shares[i];
            require(r != address(0), "Zero address");
            require(s > 0 && s <= BASIS_POINTS, "Invalid share");

            list.push(Royalty(r, uint96(s)));
            total += s;
            unchecked { ++i; }
        }

        require(total == BASIS_POINTS, "Shares must total 10000");
        emit RoyaltiesSet(contentId);
    }

    /**
     * @notice Fund royalties for a contentId. ETH is credited to recipients' balances.
     * @dev Uses pull-payments (credits balances) to avoid transfer failures during distribution.
     */
    function fundRoyalties(uint256 contentId) external payable {
        uint256 amount = msg.value;
        require(amount > 0, "No ETH sent");

        Royalty[] storage list = royalties[contentId];
        uint256 len = list.length;
        require(len > 0, "Royalties not configured");

        // distribute into pendingWithdrawals
        uint256 distributed;
        for (uint256 i; i < len; ) {
            Royalty storage r = list[i];
            uint256 payout = (amount * r.share) / BASIS_POINTS;
            if (payout > 0) {
                pendingWithdrawals[r.recipient] += payout;
                distributed += payout;
            }
            unchecked { ++i; }
        }

        // account for rounding remainder: send leftover to owner (or keep it)
        uint256 remainder = amount - distributed;
        if (remainder > 0) {
            // send remainder to owner to avoid locking funds; owner can re-distribute later
            pendingWithdrawals[owner()] += remainder;
        }
        emit RoyaltiesFunded(contentId, amount);
    }
    /**
     * @notice Withdraw credited royalty balance.
     */
    function withdrawRoyalties() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds");

        pendingWithdrawals[msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Withdraw failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice View recipients and shares for a contentId.
     */
    function getRoyalties(uint256 contentId)
        external
        view
        returns (address[] memory recipients, uint256[] memory shares)
    {
        Royalty[] storage list = royalties[contentId];
        uint256 len = list.length;
        recipients = new address[](len);
        shares = new uint256[](len);

        for (uint256 i; i < len; ) {
            recipients[i] = list[i].recipient;
            shares[i] = list[i].share;
            unchecked { ++i; }
        }
    }
    /**
     * @notice Update a recipient address for a contentId.
     * @dev Callable by the oldRecipient or the contract owner. Moves pending balance if present.
     */
    function updateRecipient(
        uint256 contentId,
        address oldRecipient,
        address newRecipient
    ) external {
        require(newRecipient != address(0), "New recipient zero");

        Royalty[] storage list = royalties[contentId];
        uint256 len = list.length;

        for (uint256 i; i < len; ) {
            if (list[i].recipient == oldRecipient) {
                require(msg.sender == oldRecipient || msg.sender == owner(), "Unauthorized");
                list[i].recipient = newRecipient;

                // move pending balance if any
                uint256 owed = pendingWithdrawals[oldRecipient];
                if (owed > 0) {
                    pendingWithdrawals[oldRecipient] = 0;
                    pendingWithdrawals[newRecipient] += owed;
                }

                emit RecipientUpdated(contentId, oldRecipient, newRecipient);
                return;
            }
            unchecked { ++i; }
        }

        revert("Recipient not found");
    }

    // Prevent accidental plain ETH transfers
    receive() external payable {
        revert("Use fundRoyalties()");
    }
}
