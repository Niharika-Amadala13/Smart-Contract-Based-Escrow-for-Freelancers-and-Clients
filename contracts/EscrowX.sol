// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SecureEscrow is ReentrancyGuard {
    enum ProjectState { Created, Funded, Approved, Cancelled, Completed, Disputed }

    struct Project {
        address client;
        address freelancer;
        uint256 amount;
        ProjectState state;
    }

    uint256 public projectCounter;
    mapping(uint256 => Project) public projects;

    // Events
    event ProjectCreated(uint256 indexed projectId, address indexed client, address indexed freelancer, uint256 amount);
    event ProjectFunded(uint256 indexed projectId, uint256 amount);
    event ProjectApproved(uint256 indexed projectId);
    event ProjectCancelled(uint256 indexed projectId);
    event FreelancerPaid(uint256 indexed projectId, address indexed freelancer, uint256 amount);
    event RefundIssued(uint256 indexed projectId, address indexed client, uint256 amount);
    event ProjectDisputed(uint256 indexed projectId);
    event ProjectAmountUpdated(uint256 indexed projectId, uint256 oldAmount, uint256 newAmount);

    // Modifiers
    modifier onlyClient(uint256 _projectId) {
        require(msg.sender == projects[_projectId].client, "Only client can perform this action");
        _;
    }

    modifier onlyFreelancer(uint256 _projectId) {
        require(msg.sender == projects[_projectId].freelancer, "Only freelancer can perform this action");
        _;
    }

    modifier projectExists(uint256 _projectId) {
        require(_projectId > 0 && _projectId <= projectCounter, "Project does not exist");
        _;
    }

    modifier inState(uint256 _projectId, ProjectState _state) {
        require(projects[_projectId].state == _state, "Invalid project state for this action");
        _;
    }

    // Create a new project
    function createProject(address _freelancer, uint256 _amount) external returns (uint256) {
        require(_freelancer != address(0), "Freelancer address is required");
        require(msg.sender != _freelancer, "Client and freelancer must differ");
        require(_amount > 0, "Amount must be greater than zero");

        projectCounter++;
        projects[projectCounter] = Project({
            client: msg.sender,
            freelancer: _freelancer,
            amount: _amount,
            state: ProjectState.Created
        });

        emit ProjectCreated(projectCounter, msg.sender, _freelancer, _amount);
        return projectCounter;
    }

    // Fund a project
    function fundProject(uint256 _projectId) external payable 
        projectExists(_projectId) 
        onlyClient(_projectId) 
        inState(_projectId, ProjectState.Created) 
    {
        Project storage project = projects[_projectId];
        require(msg.value == project.amount, "Incorrect fund amount");

        project.state = ProjectState.Funded;

        emit ProjectFunded(_projectId, msg.value);
    }

    // Approve and mark project as completed
    function approveProject(uint256 _projectId) external 
        projectExists(_projectId) 
        onlyClient(_projectId) 
        inState(_projectId, ProjectState.Funded) 
    {
        projects[_projectId].state = ProjectState.Approved;
        emit ProjectApproved(_projectId);
    }

    // Release funds to freelancer (only after approval)
    function releaseFunds(uint256 _projectId) external 
        projectExists(_projectId) 
        nonReentrant 
        onlyClient(_projectId) 
        inState(_projectId, ProjectState.Approved) 
    {
        Project storage project = projects[_projectId];

        uint256 payment = project.amount;
        project.amount = 0;
        project.state = ProjectState.Completed;

        (bool success, ) = payable(project.freelancer).call{value: payment}("");
        require(success, "Payment failed");

        emit FreelancerPaid(_projectId, project.freelancer, payment);
    }

    // Freelancer can also withdraw funds after approval (optional)
    function withdrawFunds(uint256 _projectId) external 
        projectExists(_projectId) 
        nonReentrant 
        onlyFreelancer(_projectId) 
        inState(_projectId, ProjectState.Approved) 
    {
        Project storage project = projects[_projectId];

        uint256 payment = project.amount;
        project.amount = 0;
        project.state = ProjectState.Completed;

        (bool success, ) = payable(project.freelancer).call{value: payment}("");
        require(success, "Withdrawal failed");

        emit FreelancerPaid(_projectId, msg.sender, payment);
    }

    // Cancel project and refund
    function cancelProject(uint256 _projectId) external 
        projectExists(_projectId) 
        onlyClient(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.state == ProjectState.Created || project.state == ProjectState.Funded, "Cannot cancel at this stage");

        ProjectState prevState = project.state;
        project.state = ProjectState.Cancelled;

        if (prevState == ProjectState.Funded && project.amount > 0) {
            uint256 refund = project.amount;
            project.amount = 0;

            (bool success, ) = payable(project.client).call{value: refund}("");
            require(success, "Refund failed");

            emit RefundIssued(_projectId, project.client, refund);
        }

        emit ProjectCancelled(_projectId);
    }

    // Allow dispute flagging
    function flagDispute(uint256 _projectId) external 
        projectExists(_projectId) 
    {
        require(msg.sender == projects[_projectId].client || msg.sender == projects[_projectId].freelancer, "Not authorized");
        Project storage project = projects[_projectId];
        require(project.state == ProjectState.Funded || project.state == ProjectState.Approved, "Cannot dispute this state");

        project.state = ProjectState.Disputed;
        emit ProjectDisputed(_projectId);
    }

    // Update the project amount before funding
    function updateProjectAmount(uint256 _projectId, uint256 _newAmount) external 
        projectExists(_projectId) 
        onlyClient(_projectId) 
        inState(_projectId, ProjectState.Created) 
    {
        require(_newAmount > 0, "Amount must be greater than 0");
        Project storage project = projects[_projectId];

        uint256 oldAmount = project.amount;
        project.amount = _newAmount;

        emit ProjectAmountUpdated(_projectId, oldAmount, _newAmount);
    }

    // View status
    function getProject(uint256 _projectId) external view projectExists(_projectId) returns (
        address client,
        address freelancer,
        uint256 amount,
        ProjectState state
    ) {
        Project memory p = projects[_projectId];
        return (p.client, p.freelancer, p.amount, p.state);
    }
}
