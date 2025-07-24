// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract EscrowX {
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

    event ProjectCreated(uint256 projectId, address client, address freelancer, uint256 amount);
    event ProjectFunded(uint256 projectId);
    event ProjectApproved(uint256 projectId);
    event FundsTransferredToFreelancer(uint256 projectId); // Renamed for clarity
    event ProjectCancelled(uint256 projectId);
    event FundsWithdrawn(uint256 projectId, address freelancer);
    event RefundIssued(uint256 projectId, address client);

    // Create a new project
    function createProject(address _freelancer, uint256 _amount) external returns (uint256) {
        require(_freelancer != address(0), "Invalid freelancer address");
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

    // Fund a project (escrow)
    function fundProject(uint256 _projectId) external payable {
        Project storage project = projects[_projectId];
        require(msg.sender == project.client, "Only client can fund");
        require(msg.value == project.amount, "Incorrect funding amount");
        require(!project.isFunded, "Project already funded");
        require(!project.isCancelled, "Project is cancelled");

        project.isFunded = true;
        emit ProjectFunded(_projectId);
    }

    // Approve project (client signals work is complete)
    function approveProject(uint256 _projectId) external {
        Project storage project = projects[_projectId];
        require(msg.sender == project.client, "Only client can approve");
        require(project.isFunded, "Project not funded");
        require(!project.isCancelled, "Project is cancelled");
        require(!project.isCompleted, "Already completed");

        project.isApproved = true;
        project.isCompleted = true;

        emit ProjectApproved(_projectId);
    }

    // Freelancer withdraws funds after approval
    function withdrawFunds(uint256 _projectId) external {
        Project storage project = projects[_projectId];
        require(msg.sender == project.freelancer, "Only freelancer can withdraw");
        require(project.isApproved, "Project not approved yet");
        require(project.amount > 0, "No funds to withdraw");

        uint256 payment = project.amount;
        project.amount = 0; // Prevent re-entrancy
        payable(project.freelancer).transfer(payment);

        emit FundsTransferredToFreelancer(_projectId);
        emit FundsWithdrawn(_projectId, msg.sender);
    }

    // Cancel project before approval
    function cancelProject(uint256 _projectId) external {
        Project storage project = projects[_projectId];
        require(msg.sender == project.client, "Only client can cancel");
        require(!project.isApproved, "Already approved");
        require(!project.isCancelled, "Already cancelled");

        project.isCancelled = true;

        // Refund if already funded
        if (project.isFunded && project.amount > 0) {
            uint256 refundAmount = project.amount;
            project.amount = 0;
            payable(project.client).transfer(refundAmount);
            emit RefundIssued(_projectId, msg.sender);
        }

        emit ProjectCancelled(_projectId);
    }

    function getProjectStatus(uint256 _projectId) external view returns (
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
