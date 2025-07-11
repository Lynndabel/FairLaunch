// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FairLaunch is Ownable, ReentrancyGuard {
    // State variables
    uint256 private _projectIdCounter;
    uint256 private _proposalIdCounter;
    IERC20 public fair3Token;
    
    // Constants
    uint256 public constant GRACE_PERIOD = 90 days;
    uint256 public constant VOTING_PERIOD = 14 days;
    uint256 public constant MIN_ROYALTY_RATE = 500; // 5%
    uint256 public constant MAX_ROYALTY_RATE = 1500; // 15%
    uint256 public constant BASIS_POINTS = 10000; // 100%
    
    // Enums
    enum ProjectStatus {
        Active,
        Flagged,
        Abandoned,
        InRevival,
        Revived,
        Disputed
    }
    
    enum ProposalStatus {
        Pending,
        Active,
        Approved,
        Rejected,
        Executed
    }
    
    // Structs
    struct Contributor {
        address wallet;
        uint256 contributionWeight; // Basis points (0-10000)
        string role; // "founder", "core_dev", "community", etc.
        bool isActive;
    }
    
    struct Project {
        uint256 id;
        string name;
        string description;
        string githubRepo;
        string[] techStack;
        address[] originalTeam;
        mapping(address => Contributor) contributors;
        uint256 totalContributionWeight;
        uint256 royaltyRate; // Basis points
        ProjectStatus status;
        uint256 abandonedTimestamp;
        uint256 lastActivityTimestamp;
        string abandonmentReason;
        address currentOwner;
        uint256 totalRoyaltiesDistributed;
        bool isDisputed;
    }
    
    struct RevivalProposal {
        uint256 id;
        uint256 projectId;
        address proposer;
        address[] newTeam;
        string revivalPlan;
        string[] milestones;
        uint256 requestedFunding;
        uint256 proposedRoyaltyRate;
        uint256 submissionTimestamp;
        uint256 votesFor;
        uint256 votesAgainst;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
        mapping(address => bool) voteChoice; // true = for, false = against
    }
    
    // Mappings
    mapping(uint256 => Project) public projects;
    mapping(uint256 => RevivalProposal) public revivalProposals;
    mapping(address => uint256[]) public userProjects;
    mapping(string => uint256) public githubToProjectId;
    mapping(address => uint256) public userVotingPower;
    
    // Events
    event ProjectRegistered(uint256 indexed projectId, string name, address indexed owner);
    event ProjectFlagged(uint256 indexed projectId, address indexed flagger, string reason);
    event ProjectAbandoned(uint256 indexed projectId, uint256 timestamp);
    event RevivalProposalSubmitted(uint256 indexed proposalId, uint256 indexed projectId, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProjectRevived(uint256 indexed projectId, uint256 indexed proposalId, address indexed newOwner);
    event RoyaltiesDistributed(uint256 indexed projectId, uint256 totalAmount, uint256 timestamp);
    event ContributorAdded(uint256 indexed projectId, address indexed contributor, uint256 weight);
    event DisputeRaised(uint256 indexed projectId, address indexed disputer, string reason);
    
    // Modifiers
    modifier projectExists(uint256 _projectId) {
        require(_projectId <= _projectIdCounter && _projectId > 0, "Project does not exist");
        _;
    }
    
    modifier onlyProjectOwner(uint256 _projectId) {
        require(projects[_projectId].currentOwner == msg.sender, "Not project owner");
        _;
    }
    
    modifier onlyActiveProject(uint256 _projectId) {
        require(projects[_projectId].status == ProjectStatus.Active, "Project not active");
        _;
    }
    
    modifier onlyAbandonedProject(uint256 _projectId) {
        require(projects[_projectId].status == ProjectStatus.Abandoned, "Project not abandoned");
        _;
    }
    
    constructor(address _fair3Token) Ownable(msg.sender) {
        require(_fair3Token != address(0), "FAIR3 token address cannot be zero");
        fair3Token = IERC20(_fair3Token);
    }
    
    /**
     * @dev Register a new project in the system
     */
    function registerProject(
        string memory _name,
        string memory _description,
        string memory _githubRepo,
        string[] memory _techStack,
        address[] memory _team,
        uint256[] memory _contributionWeights,
        string[] memory _roles,
        uint256 _royaltyRate
    ) external returns (uint256) {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_githubRepo).length > 0, "GitHub repo required");
        require(_team.length == _contributionWeights.length, "Team and weights length mismatch");
        require(_team.length == _roles.length, "Team and roles length mismatch");
        require(_royaltyRate >= MIN_ROYALTY_RATE && _royaltyRate <= MAX_ROYALTY_RATE, "Invalid royalty rate");
        require(githubToProjectId[_githubRepo] == 0, "GitHub repo already registered");
        
        ++_projectIdCounter;
        uint256 newProjectId = _projectIdCounter;
        
        Project storage newProject = projects[newProjectId];
        newProject.id = newProjectId;
        newProject.name = _name;
        newProject.description = _description;
        newProject.githubRepo = _githubRepo;
        newProject.techStack = _techStack;
        newProject.originalTeam = _team;
        newProject.royaltyRate = _royaltyRate;
        newProject.status = ProjectStatus.Active;
        newProject.lastActivityTimestamp = block.timestamp;
        newProject.currentOwner = msg.sender;
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _team.length; i++) {
            require(_team[i] != address(0), "Team member address cannot be zero");
            require(_contributionWeights[i] > 0, "Contribution weight must be > 0");
            totalWeight += _contributionWeights[i];
            
            newProject.contributors[_team[i]] = Contributor({
                wallet: _team[i],
                contributionWeight: _contributionWeights[i],
                role: _roles[i],
                isActive: true
            });
        }
        
        require(totalWeight == BASIS_POINTS, "Total contribution weights must equal 100%");
        newProject.totalContributionWeight = totalWeight;
        
        githubToProjectId[_githubRepo] = newProjectId;
        userProjects[msg.sender].push(newProjectId);
        
        emit ProjectRegistered(newProjectId, _name, msg.sender);
        return newProjectId;
    }
    
    /**
     * @dev Flag a project as potentially abandoned
     */
    function flagProject(uint256 _projectId, string memory _reason) 
        external 
        projectExists(_projectId) 
        onlyActiveProject(_projectId) 
    {
        require(bytes(_reason).length > 0, "Reason required");
        projects[_projectId].status = ProjectStatus.Flagged;
        emit ProjectFlagged(_projectId, msg.sender, _reason);
    }
    
    /**
     * @dev Declare a project as abandoned (after grace period)
     */
    function declareAbandoned(uint256 _projectId, string memory _reason) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Flagged, "Project must be flagged first");
        require(
            block.timestamp >= project.lastActivityTimestamp + GRACE_PERIOD,
            "Grace period not elapsed"
        );
        
        project.status = ProjectStatus.Abandoned;
        project.abandonedTimestamp = block.timestamp;
        project.abandonmentReason = _reason;
        
        emit ProjectAbandoned(_projectId, block.timestamp);
    }
    
    /**
     * @dev Submit a revival proposal for an abandoned project
     */
    function submitRevivalProposal(
        uint256 _projectId,
        address[] memory _newTeam,
        string memory _revivalPlan,
        string[] memory _milestones,
        uint256 _requestedFunding,
        uint256 _proposedRoyaltyRate
    ) external projectExists(_projectId) onlyAbandonedProject(_projectId) returns (uint256) {
        require(_newTeam.length > 0, "New team required");
        require(bytes(_revivalPlan).length > 0, "Revival plan required");
        require(_milestones.length > 0, "Milestones required");
        require(_proposedRoyaltyRate >= MIN_ROYALTY_RATE && _proposedRoyaltyRate <= MAX_ROYALTY_RATE, "Invalid royalty rate");
        
        // Check new team addresses are valid
        for (uint256 i = 0; i < _newTeam.length; i++) {
            require(_newTeam[i] != address(0), "Team member address cannot be zero");
        }
        
        ++_proposalIdCounter;
        uint256 newProposalId = _proposalIdCounter;
        
        RevivalProposal storage proposal = revivalProposals[newProposalId];
        proposal.id = newProposalId;
        proposal.projectId = _projectId;
        proposal.proposer = msg.sender;
        proposal.newTeam = _newTeam;
        proposal.revivalPlan = _revivalPlan;
        proposal.milestones = _milestones;
        proposal.requestedFunding = _requestedFunding;
        proposal.proposedRoyaltyRate = _proposedRoyaltyRate;
        proposal.submissionTimestamp = block.timestamp;
        proposal.status = ProposalStatus.Active;
        
        projects[_projectId].status = ProjectStatus.InRevival;
        
        emit RevivalProposalSubmitted(newProposalId, _projectId, msg.sender);
        return newProposalId;
    }
    
    /**
     * @dev Vote on a revival proposal
     */
    function voteOnProposal(uint256 _proposalId, bool _support) external {
        RevivalProposal storage proposal = revivalProposals[_proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(
            block.timestamp <= proposal.submissionTimestamp + VOTING_PERIOD,
            "Voting period ended"
        );
        
        uint256 votingPower = getUserVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");
        
        proposal.hasVoted[msg.sender] = true;
        proposal.voteChoice[msg.sender] = _support;
        
        if (_support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }
        
        emit VoteCast(_proposalId, msg.sender, _support, votingPower);
    }
    
    /**
     * @dev Execute a proposal (approve or reject based on votes)
     */
    function executeProposal(uint256 _proposalId) external {
        RevivalProposal storage proposal = revivalProposals[_proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(
            block.timestamp > proposal.submissionTimestamp + VOTING_PERIOD,
            "Voting period not ended"
        );
        
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        require(totalVotes > 0, "No votes cast");
        
        if (proposal.votesFor > proposal.votesAgainst) {
            proposal.status = ProposalStatus.Approved;
            _reviveProject(proposal.projectId, _proposalId);
        } else {
            proposal.status = ProposalStatus.Rejected;
            projects[proposal.projectId].status = ProjectStatus.Abandoned;
        }
    }
    
    /**
     * @dev Internal function to revive a project
     */
    function _reviveProject(uint256 _projectId, uint256 _proposalId) internal {
        Project storage project = projects[_projectId];
        RevivalProposal storage proposal = revivalProposals[_proposalId];
        
        project.status = ProjectStatus.Revived;
        project.currentOwner = proposal.proposer;
        project.royaltyRate = proposal.proposedRoyaltyRate;
        project.lastActivityTimestamp = block.timestamp;
        
        userProjects[proposal.proposer].push(_projectId);
        
        emit ProjectRevived(_projectId, _proposalId, proposal.proposer);
    }
    
    /**
     * @dev Distribute royalties to original contributors
     */
    function distributeRoyalties(uint256 _projectId) external payable projectExists(_projectId) nonReentrant {
        require(msg.value > 0, "No royalties to distribute");
        
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Revived, "Project not revived");
        require(project.totalContributionWeight > 0, "No contributors to distribute to");
        
        uint256 totalRoyalty = (msg.value * project.royaltyRate) / BASIS_POINTS;
        uint256 distributedAmount = 0;
        
        // Distribute to original contributors based on their weight
        for (uint256 i = 0; i < project.originalTeam.length; i++) {
            address contributor = project.originalTeam[i];
            require(contributor != address(0), "Invalid contributor address");
            
            Contributor storage contributorData = project.contributors[contributor];
            
            if (contributorData.isActive && contributorData.contributionWeight > 0) {
                uint256 contributorShare = (totalRoyalty * contributorData.contributionWeight) / project.totalContributionWeight;
                if (contributorShare > 0) {
                    distributedAmount += contributorShare;
                    (bool success, ) = payable(contributor).call{value: contributorShare}("");
                    require(success, "Transfer to contributor failed");
                }
            }
        }
        
        // Send remaining amount including platform fee to contract owner
        uint256 remaining = msg.value - distributedAmount;
        if (remaining > 0) {
            (bool success, ) = payable(owner()).call{value: remaining}("");
            require(success, "Transfer to owner failed");
        }
        
        project.totalRoyaltiesDistributed += distributedAmount;
        emit RoyaltiesDistributed(_projectId, distributedAmount, block.timestamp);
    }
    
    /**
     * @dev Add or update contributor to a project
     */
    function updateContributor(
        uint256 _projectId,
        address _contributor,
        uint256 _weight,
        string memory _role,
        bool _isActive
    ) external projectExists(_projectId) onlyProjectOwner(_projectId) {
        require(_contributor != address(0), "Contributor address cannot be zero");
        require(bytes(_role).length > 0, "Role cannot be empty");
        
        Project storage project = projects[_projectId];
        
        uint256 oldWeight = project.contributors[_contributor].contributionWeight;
        project.contributors[_contributor] = Contributor({
            wallet: _contributor,
            contributionWeight: _weight,
            role: _role,
            isActive: _isActive
        });
        
        project.totalContributionWeight = project.totalContributionWeight - oldWeight + _weight;
        require(project.totalContributionWeight <= BASIS_POINTS, "Total weight exceeds 100%");
        
        emit ContributorAdded(_projectId, _contributor, _weight);
    }
    
    /**
     * @dev Raise a dispute about project abandonment or revival
     */
    function raiseDispute(uint256 _projectId, string memory _reason) 
        external 
        projectExists(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(!project.isDisputed, "Already disputed");
        require(bytes(_reason).length > 0, "Reason required");
        
        // Only original contributors or current owner can raise disputes
        require(
            project.contributors[msg.sender].isActive || 
            project.currentOwner == msg.sender,
            "Not authorized to dispute"
        );
        
        project.isDisputed = true;
        project.status = ProjectStatus.Disputed;
        
        emit DisputeRaised(_projectId, msg.sender, _reason);
    }
    
    /**
     * @dev Update project activity timestamp (called by original owner)
     */
    function updateActivity(uint256 _projectId) 
        external 
        projectExists(_projectId) 
        onlyProjectOwner(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Active || project.status == ProjectStatus.Flagged, "Invalid status");
        
        project.lastActivityTimestamp = block.timestamp;
        if (project.status == ProjectStatus.Flagged) {
            project.status = ProjectStatus.Active;
        }
    }
    
    /**
     * @dev Set voting power for users (called by governance system)
     */
    function setVotingPower(address _user, uint256 _power) external onlyOwner {
        require(_user != address(0), "User address cannot be zero");
        userVotingPower[_user] = _power;
    }
    
    /**
     * @dev Get user's voting power (based on FAIR3 tokens + reputation)
     */
    function getUserVotingPower(address _user) public view returns (uint256) {
        if (_user == address(0)) return 0;
        uint256 tokenBalance = fair3Token.balanceOf(_user);
        uint256 reputationPower = userVotingPower[_user];
        return tokenBalance + reputationPower;
    }
    
    /**
     * @dev Get project details
     */
    function getProject(uint256 _projectId) external view projectExists(_projectId) returns (
        string memory name,
        string memory description,
        string memory githubRepo,
        string[] memory techStack,
        address[] memory originalTeam,
        uint256 royaltyRate,
        ProjectStatus status,
        address currentOwner,
        uint256 abandonedTimestamp,
        uint256 lastActivityTimestamp
    ) {
        Project storage project = projects[_projectId];
        return (
            project.name,
            project.description,
            project.githubRepo,
            project.techStack,
            project.originalTeam,
            project.royaltyRate,
            project.status,
            project.currentOwner,
            project.abandonedTimestamp,
            project.lastActivityTimestamp
        );
    }
    
    /**
     * @dev Get contributor info for a project
     */
    function getContributor(uint256 _projectId, address _contributor) 
        external 
        view 
        projectExists(_projectId) 
        returns (uint256 weight, string memory role, bool isActive) 
    {
        Contributor storage contributor = projects[_projectId].contributors[_contributor];
        return (contributor.contributionWeight, contributor.role, contributor.isActive);
    }
    
    /**
     * @dev Get revival proposal details
     */
    function getRevivalProposal(uint256 _proposalId) external view returns (
        uint256 projectId,
        address proposer,
        address[] memory newTeam,
        string memory revivalPlan,
        string[] memory milestones,
        uint256 requestedFunding,
        uint256 proposedRoyaltyRate,
        uint256 votesFor,
        uint256 votesAgainst,
        ProposalStatus status
    ) {
        RevivalProposal storage proposal = revivalProposals[_proposalId];
        return (
            proposal.projectId,
            proposal.proposer,
            proposal.newTeam,
            proposal.revivalPlan,
            proposal.milestones,
            proposal.requestedFunding,
            proposal.proposedRoyaltyRate,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.status
        );
    }
    
    /**
     * @dev Get user's projects
     */
    function getUserProjects(address _user) external view returns (uint256[] memory) {
        return userProjects[_user];
    }
    
    /**
     * @dev Get total number of projects
     */
    function getTotalProjects() external view returns (uint256) {
        return _projectIdCounter;
    }
    
    /**
     * @dev Get total number of proposals
     */
    function getTotalProposals() external view returns (uint256) {
        return _proposalIdCounter;
    }
    
    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        // Implementation for emergency pause
    }
    
    /**
     * @dev Withdraw accumulated platform fees
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
}