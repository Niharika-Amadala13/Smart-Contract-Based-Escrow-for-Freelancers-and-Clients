// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EscrowX is ReentrancyGuard {
    struct Project {
        address client;
        address freelancer;
        uint256 amount;
        bool isApproved;
        bool isCancelled;
        bool isFunded;
        bool isCompleted;
    }

    mapping(uint256 => Project) public projects;
    uint256 public projectCounter;

    event ProjectCreated(uint256 indexed projectId, address indexed client, address indexed freelancer, uint256 amount);
    event ProjectFunded(uint256 indexed projectId, uint256 amount);
    event ProjectApproved(uint256 indexed projectId);
    event ProjectCancelled(uint256 indexed projectId);
    event FreelancerPaid(uint256 indexed projectId, address indexed freelancer, uint256 amount);
    event RefundIssued(uint256 indexed projectId, address indexed client, uint256 amount);
    event AmountUpdated(uint256 indexed projectId, uint256 oldAmount, uint256 newAmount);

    modifier onlyClient(uint256 _projectId) {
        require(msg.sender == projects[_projectId].client, "Only client allowed");
        _;
    }

    modifier onlyFreelancer(uint256 _projectId) {
        require(msg.sender == projects[_projectId].freelancer, "Only freelancer allowed");
        _;
    }

    modifier projectExists(uint256 _projectId) {
        require(_projectId > 0 && _projectId <= projectCounter, "Invalid project ID");
        _;
    }

    function createProject(address _freelancer, uint256 _amount) external returns (uint256) {
        require(_freelancer != address(0), "Freelancer address required");
        require(_freelancer != msg.sender, "Client and freelancer must be different");
        require(_amount > 0, "Amount must be greater than zero");

        projectCounter++;
        projects[projectCounter] = Project({
            client: msg.sender,
            freelancer: _freelancer,
            amount: _amount,
            isApproved: false,
            isCancelled: false,
            isFunded: false,
            isCompleted: false
        });

        emit ProjectCreated(projectCounter, msg.sender, _freelancer, _amount);
        return projectCounter;
    }

    function updateProjectAmount(uint256 _projectId, uint256 _newAmount) external projectExists(_projectId) onlyClient(_projectId) {
        Project storage project = projects[_projectId];
        require(!project.isFunded, "Cannot update amount after funding");
        require(!project.isCancelled, "Cannot update cancelled project");
        require(_newAmount > 0, "New amount must be greater than zero");

        uint256 oldAmount = project.amount;
        project.amount = _newAmount;

        emit AmountUpdated(_projectId, oldAmount, _newAmount);
    }

    function fundProject(uint256 _projectId) external payable projectExists(_projectId) onlyClient(_projectId) {
        Project storage project = projects[_projectId];
        require(!project.isFunded, "Already funded");
        require(!project.isCancelled, "Project is cancelled");
        require(msg.value == project.amount, "Incorrect funding amount");

        project.isFunded = true;
        emit ProjectFunded(_projectId, msg.value);
    }

    function approveProject(uint256 _projectId) external projectExists(_projectId) onlyClient(_projectId) {
        Project storage project = projects[_projectId];
        require(project.isFunded, "Not funded yet");
        require(!project.isCancelled, "Project is cancelled");
        require(!project.isApproved, "Already approved");

        project.isApproved = true;
        project.isCompleted = true;

        emit ProjectApproved(_projectId);
    }

    function withdrawFunds(uint256 _projectId) external nonReentrant projectExists(_projectId) onlyFreelancer(_projectId) {
        Project storage project = projects[_projectId];
        require(project.isApproved, "Project not approved");
        require(project.amount > 0, "No funds to withdraw");

        uint256 payment = project.amount;
        project.amount = 0;

        (bool success, ) = payable(msg.sender).call{value: payment}("");
        require(success, "Transfer failed");

        emit FreelancerPaid(_projectId, msg.sender, payment);
    }

    function cancelProject(uint256 _projectId) external projectExists(_projectId) onlyClient(_projectId) {
        Project storage project = projects[_projectId];
        require(!project.isApproved, "Already approved");
        require(!project.isCancelled, "Already cancelled");

        project.isCancelled = true;

        if (project.isFunded && project.amount > 0) {
            uint256 refundAmount = project.amount;
            project.amount = 0;

            (bool success, ) = payable(project.client).call{value: refundAmount}("");
            require(success, "Refund failed");

            emit RefundIssued(_projectId, project.client, refundAmount);
        }

        emit ProjectCancelled(_projectId);
    }

    function getProjectStatus(uint256 _projectId) external view projectExists(_projectId) returns (
        address client,
        address freelancer,
        uint256 amount,
        bool isApproved,
        bool isCancelled,
        bool isFunded,
        bool isCompleted
    ) {
        Project memory project = projects[_projectId];
        return (
            project.client,
            project.freelancer,
            project.amount,
            project.isApproved,
            project.isCancelled,
            project.isFunded,
            project.isCompleted
        );
    }
}
