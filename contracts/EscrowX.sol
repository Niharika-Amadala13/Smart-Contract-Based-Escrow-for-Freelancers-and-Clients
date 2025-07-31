// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SecureEscrow is ReentrancyGuard, Ownable {
    enum ProjectState { Created, Funded, Approved, Cancelled, Completed, Disputed }

    struct Project {
        address client;
        address freelancer;
        uint256 amount;
        ProjectState state;
        uint256 createdAt;
        string title;
        string description;
    }

    uint256 public projectCounter;
    mapping(uint256 => Project) public projects;
    address public arbitrator;
    uint256 public constant TIMEOUT = 7 days;  // Auto-approval period
    uint256 public platformFeePercent = 2;     // 2% platform fee

    // Events
    event ProjectCreated(uint256 indexed projectId, address indexed client, address indexed freelancer, uint256 amount);
    event ProjectFunded(uint256 indexed projectId, uint256 amount);
    event ProjectApproved(uint256 indexed projectId);
    event ProjectCancelled(uint256 indexed projectId);
    event FreelancerPaid(uint256 indexed projectId, address indexed freelancer, uint256 amount);
    event RefundIssued(uint256 indexed projectId, address indexed client, uint256 amount);
    event ProjectDisputed(uint256 indexed projectId);
    event ProjectResolved(uint256 indexed projectId, address recipient, uint256 amount);
    event ProjectAmountUpdated(uint256 indexed projectId, uint256 oldAmount, uint256 newAmount);

    constructor(address _arbitrator) {
        require(_arbitrator != address(0), "Invalid arbitrator address");
        arbitrator = _arbitrator;
    }

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

    modifier inState(uint256 _projectId, ProjectState _state) {
        require(projects[_projectId].state == _state, "Invalid state for this action");
        _;
    }

    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, "Only arbitrator allowed");
        _;
    }

    // --- MAIN FUNCTIONS ---

    function createProject(address _freelancer, uint256 _amount, string calldata _title, string calldata _description)
        external returns (uint256)
    {
        require(_freelancer != address(0), "Freelancer required");
        require(_amount > 0, "Amount must be > 0");
        require(msg.sender != _freelancer, "Client cannot be freelancer");

        projectCounter++;
        projects[projectCounter] = Project({
            client: msg.sender,
            freelancer: _freelancer,
            amount: _amount,
            state: ProjectState.Created,
            createdAt: block.timestamp,
            title: _title,
            description: _description
        });

        emit ProjectCreated(projectCounter, msg.sender, _freelancer, _amount);
        return projectCounter;
    }

    function fundProject(uint256 _projectId)
        external payable projectExists(_projectId) onlyClient(_projectId) inState(_projectId, ProjectState.Created)
    {
        Project storage project = projects[_projectId];
        require(msg.value == project.amount, "Incorrect fund amount");

        project.state = ProjectState.Funded;
        emit ProjectFunded(_projectId, msg.value);
    }

    function approveProject(uint256 _projectId)
        external projectExists(_projectId) onlyClient(_projectId) inState(_projectId, ProjectState.Funded)
    {
        projects[_projectId].state = ProjectState.Approved;
        emit ProjectApproved(_projectId);
    }

    function releaseFunds(uint256 _projectId)
        external projectExists(_projectId) nonReentrant onlyClient(_projectId) inState(_projectId, ProjectState.Approved)
    {
        _completeAndPay(_projectId, projects[_projectId].freelancer);
    }

    function withdrawFundsAfterTimeout(uint256 _projectId)
        external projectExists(_projectId) nonReentrant onlyFreelancer(_projectId)
    {
        Project storage project = projects[_projectId];
        require(project.state == ProjectState.Funded, "Not eligible for timeout withdrawal");
        require(block.timestamp >= project.createdAt + TIMEOUT, "Timeout not reached");

        _completeAndPay(_projectId, project.freelancer);
    }

    function withdrawFunds(uint256 _projectId)
        external projectExists(_projectId) nonReentrant onlyFreelancer(_projectId) inState(_projectId, ProjectState.Approved)
    {
        _completeAndPay(_projectId, msg.sender);
    }

    function cancelProject(uint256 _projectId)
        external projectExists(_projectId) onlyClient(_projectId)
    {
        Project storage project = projects[_projectId];
        require(project.state == ProjectState.Created || project.state == ProjectState.Funded, "Cannot cancel now");

        ProjectState prev = project.state;
        project.state = ProjectState.Cancelled;

        if (prev == ProjectState.Funded && project.amount > 0) {
            uint256 refund = project.amount;
            project.amount = 0;
            (bool success, ) = payable(project.client).call{value: refund}("");
            require(success, "Refund failed");
            emit RefundIssued(_projectId, project.client, refund);
        }

        emit ProjectCancelled(_projectId);
    }

    function flagDispute(uint256 _projectId)
        external projectExists(_projectId)
    {
        require(
            msg.sender == projects[_projectId].client || msg.sender == projects[_projectId].freelancer,
            "Unauthorized"
        );
        Project storage project = projects[_projectId];
        require(project.state == ProjectState.Funded || project.state == ProjectState.Approved, "Cannot dispute");

        project.state = ProjectState.Disputed;
        emit ProjectDisputed(_projectId);
    }

    function resolveDispute(uint256 _projectId, bool releaseToFreelancer)
        external projectExists(_projectId) onlyArbitrator inState(_projectId, ProjectState.Disputed) nonReentrant
    {
        Project storage project = projects[_projectId];
        uint256 payout = project.amount;
        project.amount = 0;
        project.state = ProjectState.Completed;

        address recipient = releaseToFreelancer ? project.freelancer : project.client;

        (bool success, ) = payable(recipient).call{value: payout}("");
        require(success, "Transfer failed");

        emit ProjectResolved(_projectId, recipient, payout);
    }

    function updateProjectAmount(uint256 _projectId, uint256 _newAmount)
        external projectExists(_projectId) onlyClient(_projectId) inState(_projectId, ProjectState.Created)
    {
        require(_newAmount > 0, "Invalid new amount");
        Project storage project = projects[_projectId];
        uint256 oldAmount = project.amount;
        project.amount = _newAmount;

        emit ProjectAmountUpdated(_projectId, oldAmount, _newAmount);
    }

    // --- INTERNAL ---

    function _completeAndPay(uint256 _projectId, address recipient) internal {
        Project storage project = projects[_projectId];
        uint256 total = project.amount;
        project.amount = 0;
        project.state = ProjectState.Completed;

        uint256 fee = (total * platformFeePercent) / 100;
        uint256 payout = total - fee;

        (bool success1, ) = payable(recipient).call{value: payout}("");
        require(success1, "Payment failed");

        if (fee > 0) {
            (bool success2, ) = payable(owner()).call{value: fee}("");
            require(success2, "Fee transfer failed");
        }

        emit FreelancerPaid(_projectId, recipient, payout);
    }

    // --- VIEW FUNCTIONS ---

    function getProject(uint256 _projectId)
        external view projectExists(_projectId) returns (
            address client,
            address freelancer,
            uint256 amount,
            ProjectState state,
            uint256 createdAt,
            string memory title,
            string memory description
        )
    {
        Project memory p = projects[_projectId];
        return (p.client, p.freelancer, p.amount, p.state, p.createdAt, p.title, p.description);
    }

    // --- ADMIN FUNCTIONS ---

    function updateArbitrator(address _newArbitrator) external onlyOwner {
        require(_newArbitrator != address(0), "Invalid arbitrator");
        arbitrator = _newArbitrator;
    }

    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 10, "Fee too high
