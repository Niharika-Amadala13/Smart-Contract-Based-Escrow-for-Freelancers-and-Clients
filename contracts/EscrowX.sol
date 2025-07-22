// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract EscrowX {
    // Struct to store project details
    struct Project {
        address client;
        address freelancer;
        uint256 amount;
        bool isApproved;
        bool isCancelled;
        bool isFunded;
        bool isCompleted;
    }

    // Mapping to store projects
    mapping(uint256 => Project) public projects;
    uint256 public projectCounter;

    // Events to log important actions
    event ProjectCreated(uint256 projectId, address client, address freelancer, uint256 amount);
    event ProjectFunded(uint256 projectId);
    event ProjectApproved(uint256 projectId);
    event FundsReleased(uint256 projectId);
    event ProjectCancelled(uint256 projectId);

    // Function to create a new escrow project
    function createProject(address _freelancer, uint256 _amount) external returns (uint256) {
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

    // Function to fund the escrow project
    function fundProject(uint256 _projectId) external payable {
        Project storage project = projects[_projectId];
        require(msg.sender == project.client, "Only client can fund");
        require(msg.value == project.amount, "Incorrect funding amount");
        require(!project.isFunded, "Project already funded");

        project.isFunded = true;
        emit ProjectFunded(_projectId);
    }

    // Function to approve project completion
    function approveProject(uint256 _projectId) external {
        Project storage project = projects[_projectId];
        require(msg.sender == project.client, "Only client can approve");
        require(project.isFunded, "Project not funded");
        require(!project.isCompleted, "Project already completed");

        project.isApproved = true;
        project.isCompleted = true;
        payable(project.freelancer).transfer(project.amount);
        
        emit ProjectApproved(_projectId);
        emit FundsReleased(_projectId);
    }
}