// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/FairLaunch.sol";
import "../src/MockERC20.sol";

contract FairLaunchTest is Test {
    FairLaunch public fairLaunch;
    MockERC20 public fair3Token;
    
    // Test accounts
    address public owner = address(this);
    address public addr1 = makeAddr("addr1");
    address public addr2 = makeAddr("addr2");
    address public addr3 = makeAddr("addr3");
    address public addr4 = makeAddr("addr4");
    address public addr5 = makeAddr("addr5");
    
    // Constants
    uint256 public constant GRACE_PERIOD = 90 days;
    uint256 public constant VOTING_PERIOD = 14 days;
    uint256 public constant MIN_ROYALTY_RATE = 500; // 5%
    uint256 public constant MAX_ROYALTY_RATE = 1500; // 15%
    uint256 public constant BASIS_POINTS = 10000; // 100%
    
    // Test data
    address[] public originalTeam;
    address[] public newTeam;
    uint256[] public contributionWeights;
    string[] public roles;
    string[] public techStack;
    string[] public milestones;

    function setUp() public {
        // Deploy FAIR3 token
        fair3Token = new MockERC20("FAIR3", "FAIR3", 1_000_000 ether);
        
        // Deploy FairLaunch contract
        fairLaunch = new FairLaunch(address(fair3Token));
        
        // Setup test arrays
        originalTeam = [addr1, addr2];
        newTeam = [addr3, addr4];
        contributionWeights = [6000, 4000]; // 60%, 40%
        roles = ["Founder", "Developer"];
        techStack = ["Solidity", "React"];
        milestones = ["Milestone 1", "Milestone 2"];
        
        // Distribute tokens for voting
        fair3Token.transfer(addr1, 1000 ether);
        fair3Token.transfer(addr2, 1000 ether);
        fair3Token.transfer(addr3, 1000 ether);
        fair3Token.transfer(addr4, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public {
        assertEq(fairLaunch.owner(), owner);
        assertEq(address(fairLaunch.fair3Token()), address(fair3Token));
    }

    function test_deploymentRevertsWithZeroAddress() public {
        vm.expectRevert("FAIR3 token address cannot be zero");
        new FairLaunch(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        PROJECT REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerProject() public {
        vm.prank(addr1);
        
        vm.expectEmit(true, true, false, true);
        emit FairLaunch.ProjectRegistered(1, "Test Project", addr1);
        
        uint256 projectId = fairLaunch.registerProject(
            "Test Project",
            "A test project",
            "https://github.com/test/project",
            techStack,
            originalTeam,
            contributionWeights,
            roles,
            1000
        );
        
        assertEq(projectId, 1);
        
        (
            string memory name,
            string memory description,
            string memory githubRepo,
            string[] memory returnedTechStack,
            address[] memory returnedTeam,
            uint256 royaltyRate,
            FairLaunch.ProjectStatus status,
            address currentOwner,
            uint256 abandonedTimestamp,
            uint256 lastActivityTimestamp
        ) = fairLaunch.getProject(1);
        
        assertEq(name, "Test Project");
        assertEq(description, "A test project");
        assertEq(githubRepo, "https://github.com/test/project");
        assertEq(returnedTechStack.length, 2);
        assertEq(returnedTeam.length, 2);
        assertEq(returnedTeam[0], addr1);
        assertEq(returnedTeam[1], addr2);
        assertEq(royaltyRate, 1000);
        assertEq(uint256(status), 0); // ProjectStatus.Active
        assertEq(currentOwner, addr1);
        assertEq(abandonedTimestamp, 0);
        assertGt(lastActivityTimestamp, 0);
    }

    function test_registerProjectRevertsWithZeroTeamMember() public {
        address[] memory invalidTeam = new address[](2);
        invalidTeam[0] = address(0);
        invalidTeam[1] = addr2;
        
        vm.prank(addr1);
        vm.expectRevert("Team member address cannot be zero");
        fairLaunch.registerProject(
            "Test Project",
            "Description",
            "https://github.com/test/project",
            techStack,
            invalidTeam,
            contributionWeights,
            roles,
            1000
        );
    }

    function test_registerProjectRevertsWithInvalidWeights() public {
        uint256[] memory invalidWeights = new uint256[](2);
        invalidWeights[0] = 5000;
        invalidWeights[1] = 4000; // Only 90%
        
        vm.prank(addr1);
        vm.expectRevert("Total contribution weights must equal 100%");
        fairLaunch.registerProject(
            "Test Project",
            "Description",
            "https://github.com/test/project",
            techStack,
            originalTeam,
            invalidWeights,
            roles,
            1000
        );
    }

    function test_registerProjectRevertsWithInvalidRoyaltyRate() public {
        vm.prank(addr1);
        vm.expectRevert("Invalid royalty rate");
        fairLaunch.registerProject(
            "Test Project",
            "Description",
            "https://github.com/test/project",
            techStack,
            originalTeam,
            contributionWeights,
            roles,
            2000 // 20% - too high
        );
    }

    function test_registerProjectRevertsWithDuplicateGithubRepo() public {
        string memory githubRepo = "https://github.com/test/project";
        
        vm.prank(addr1);
        fairLaunch.registerProject(
            "Test Project 1",
            "Description",
            githubRepo,
            techStack,
            originalTeam,
            contributionWeights,
            roles,
            1000
        );
        
        vm.prank(addr2);
        vm.expectRevert("GitHub repo already registered");
        fairLaunch.registerProject(
            "Test Project 2",
            "Description",
            githubRepo, // Same repo
            techStack,
            originalTeam,
            contributionWeights,
            roles,
            1000
        );
    }

    /*//////////////////////////////////////////////////////////////
                        PROJECT LIFECYCLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_flagProject() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectEmit(true, true, false, true);
        emit FairLaunch.ProjectFlagged(projectId, addr3, "No activity for 6 months");
        
        fairLaunch.flagProject(projectId, "No activity for 6 months");
        
        (, , , , , , FairLaunch.ProjectStatus status, , , ) = fairLaunch.getProject(projectId);
        assertEq(uint256(status), 1); // ProjectStatus.Flagged
    }

    function test_flagProjectRevertsWithEmptyReason() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Reason required");
        fairLaunch.flagProject(projectId, "");
    }

    function test_declareAbandoned() public {
        uint256 projectId = _registerTestProject();
        
        // Flag project first
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        // Fast forward time beyond grace period
        vm.warp(block.timestamp + GRACE_PERIOD + 1);
        
        vm.prank(addr3);
        vm.expectEmit(true, false, false, true);
        emit FairLaunch.ProjectAbandoned(projectId, block.timestamp);
        
        fairLaunch.declareAbandoned(projectId, "Grace period elapsed");
        
        (, , , , , , FairLaunch.ProjectStatus status, , , ) = fairLaunch.getProject(projectId);
        assertEq(uint256(status), 2); // ProjectStatus.Abandoned
    }

    function test_declareAbandonedRevertsBeforeGracePeriod() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        vm.prank(addr3);
        vm.expectRevert("Grace period not elapsed");
        fairLaunch.declareAbandoned(projectId, "Too early");
    }

    function test_updateActivity() public {
        uint256 projectId = _registerTestProject();
        
        // Flag project
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        // Owner updates activity
        vm.prank(addr1);
        fairLaunch.updateActivity(projectId);
        
        (, , , , , , FairLaunch.ProjectStatus status, , , ) = fairLaunch.getProject(projectId);
        assertEq(uint256(status), 0); // ProjectStatus.Active
    }

    /*//////////////////////////////////////////////////////////////
                        REVIVAL PROPOSAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_submitRevivalProposal() public {
        uint256 projectId = _abandonProject();
        
        vm.prank(addr3);
        vm.expectEmit(true, true, true, false);
        emit FairLaunch.RevivalProposalSubmitted(1, projectId, addr3);
        
        uint256 proposalId = fairLaunch.submitRevivalProposal(
            projectId,
            newTeam,
            "We will revive this project with new features",
            milestones,
            10 ether,
            800 // 8% royalty
        );
        
        assertEq(proposalId, 1);
        
        (
            uint256 returnedProjectId,
            address proposer,
            address[] memory returnedNewTeam,
            string memory revivalPlan,
            string[] memory returnedMilestones,
            uint256 requestedFunding,
            uint256 proposedRoyaltyRate,
            uint256 votesFor,
            uint256 votesAgainst,
            FairLaunch.ProposalStatus status
        ) = fairLaunch.getRevivalProposal(1);
        
        assertEq(returnedProjectId, projectId);
        assertEq(proposer, addr3);
        assertEq(returnedNewTeam.length, 2);
        assertEq(returnedNewTeam[0], addr3);
        assertEq(returnedNewTeam[1], addr4);
        assertEq(bytes(revivalPlan).length > 0, true);
        assertEq(returnedMilestones.length, 2);
        assertEq(requestedFunding, 10 ether);
        assertEq(proposedRoyaltyRate, 800);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertEq(uint256(status), 1); // ProposalStatus.Active
    }

    function test_submitRevivalProposalRevertsWithZeroAddress() public {
        uint256 projectId = _abandonProject();
        
        address[] memory invalidTeam = new address[](2);
        invalidTeam[0] = address(0);
        invalidTeam[1] = addr4;
        
        vm.prank(addr3);
        vm.expectRevert("Team member address cannot be zero");
        fairLaunch.submitRevivalProposal(
            projectId,
            invalidTeam,
            "Revival plan",
            milestones,
            10 ether,
            800
        );
    }

    function test_submitRevivalProposalRevertsWithInvalidRoyalty() public {
        uint256 projectId = _abandonProject();
        
        vm.prank(addr3);
        vm.expectRevert("Invalid royalty rate");
        fairLaunch.submitRevivalProposal(
            projectId,
            newTeam,
            "Revival plan",
            milestones,
            10 ether,
            300 // Too low
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VOTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_voteOnProposal() public {
        (uint256 projectId, uint256 proposalId) = _setupRevivalProposal();
        
        uint256 expectedVotingPower = fairLaunch.getUserVotingPower(addr1);
        
        vm.prank(addr1);
        vm.expectEmit(true, true, false, true);
        emit FairLaunch.VoteCast(proposalId, addr1, true, expectedVotingPower);
        
        fairLaunch.voteOnProposal(proposalId, true);
        
        (, , , , , , , uint256 votesFor, , ) = fairLaunch.getRevivalProposal(proposalId);
        assertEq(votesFor, expectedVotingPower);
    }

    function test_voteOnProposalRevertsDoubleVoting() public {
        (, uint256 proposalId) = _setupRevivalProposal();
        
        vm.prank(addr1);
        fairLaunch.voteOnProposal(proposalId, true);
        
        vm.prank(addr1);
        vm.expectRevert("Already voted");
        fairLaunch.voteOnProposal(proposalId, false);
    }

    function test_voteOnProposalRevertsNoVotingPower() public {
        (, uint256 proposalId) = _setupRevivalProposal();
        
        vm.prank(addr5); // addr5 has no tokens
        vm.expectRevert("No voting power");
        fairLaunch.voteOnProposal(proposalId, true);
    }

    function test_executeProposalApproved() public {
        (uint256 projectId, uint256 proposalId) = _setupRevivalProposal();
        
        // Vote in favor
        vm.prank(addr1);
        fairLaunch.voteOnProposal(proposalId, true);
        
        vm.prank(addr2);
        fairLaunch.voteOnProposal(proposalId, true);
        
        // Wait for voting period to end
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        vm.expectEmit(true, true, true, false);
        emit FairLaunch.ProjectRevived(projectId, proposalId, addr3);
        
        fairLaunch.executeProposal(proposalId);
        
        (, , , , , , FairLaunch.ProjectStatus status, address currentOwner, , ) = fairLaunch.getProject(projectId);
        assertEq(uint256(status), 4); // ProjectStatus.Revived
        assertEq(currentOwner, addr3);
    }

    function test_executeProposalRejected() public {
        (uint256 projectId, uint256 proposalId) = _setupRevivalProposal();
        
        // Vote against
        vm.prank(addr1);
        fairLaunch.voteOnProposal(proposalId, false);
        
        vm.prank(addr2);
        fairLaunch.voteOnProposal(proposalId, false);
        
        vm.prank(addr3);
        fairLaunch.voteOnProposal(proposalId, true);
        
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        fairLaunch.executeProposal(proposalId);
        
        (, , , , , , , , , FairLaunch.ProposalStatus proposalStatus) = fairLaunch.getRevivalProposal(proposalId);
        assertEq(uint256(proposalStatus), 3); // ProposalStatus.Rejected
        
        (, , , , , , FairLaunch.ProjectStatus projectStatus, , , ) = fairLaunch.getProject(projectId);
        assertEq(uint256(projectStatus), 2); // ProjectStatus.Abandoned
    }

    /*//////////////////////////////////////////////////////////////
                        ROYALTY DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_distributeRoyalties() public {
        uint256 projectId = _setupRevivedProject();
        
        uint256 royaltyAmount = 1 ether;
        uint256 expectedRoyalty = (royaltyAmount * 800) / 10000; // 8% of 1 ETH
        uint256 expectedAddr1Share = (expectedRoyalty * 6000) / 10000; // 60% of royalty
        uint256 expectedAddr2Share = (expectedRoyalty * 4000) / 10000; // 40% of royalty
        
        uint256 addr1BalanceBefore = addr1.balance;
        uint256 addr2BalanceBefore = addr2.balance;
        
        vm.prank(addr3);
        vm.expectEmit(true, false, false, false);
        emit FairLaunch.RoyaltiesDistributed(projectId, expectedRoyalty, block.timestamp);
        
        fairLaunch.distributeRoyalties{value: royaltyAmount}(projectId);
        
        uint256 addr1BalanceAfter = addr1.balance;
        uint256 addr2BalanceAfter = addr2.balance;
        
        assertEq(addr1BalanceAfter - addr1BalanceBefore, expectedAddr1Share);
        assertEq(addr2BalanceAfter - addr2BalanceBefore, expectedAddr2Share);
    }

    function test_distributeRoyaltiesRevertsNoValue() public {
        uint256 projectId = _setupRevivedProject();
        
        vm.prank(addr3);
        vm.expectRevert("No royalties to distribute");
        fairLaunch.distributeRoyalties{value: 0}(projectId);
    }

    function test_distributeRoyaltiesRevertsNotRevived() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Project not revived");
        fairLaunch.distributeRoyalties{value: 1 ether}(projectId);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateActivityRevertsNotOwner() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Not project owner");
        fairLaunch.updateActivity(projectId);
    }

    function test_updateContributorRevertsNotOwner() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Not project owner");
        fairLaunch.updateContributor(projectId, addr5, 1000, "Tester", true);
    }

    function test_setVotingPowerRevertsNotOwner() public {
        vm.prank(addr1);
        vm.expectRevert("Ownable: caller is not the owner");
        fairLaunch.setVotingPower(addr2, 1000);
    }

    function test_withdrawFeesRevertsNotOwner() public {
        vm.prank(addr1);
        vm.expectRevert("Ownable: caller is not the owner");
        fairLaunch.withdrawFees();
    }

    /*//////////////////////////////////////////////////////////////
                            DISPUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_raiseDispute() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr1);
        vm.expectEmit(true, true, false, true);
        emit FairLaunch.DisputeRaised(projectId, addr1, "Unfair abandonment");
        
        fairLaunch.raiseDispute(projectId, "Unfair abandonment");
        
        (, , , , , , FairLaunch.ProjectStatus status, , , ) = fairLaunch.getProject(projectId);
        assertEq(uint256(status), 5); // ProjectStatus.Disputed
    }

    function test_raiseDisputeRevertsNotAuthorized() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr5);
        vm.expectRevert("Not authorized to dispute");
        fairLaunch.raiseDispute(projectId, "Random dispute");
    }

    function test_raiseDisputeRevertsEmptyReason() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr1);
        vm.expectRevert("Reason required");
        fairLaunch.raiseDispute(projectId, "");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _registerTestProject() internal returns (uint256) {
        vm.prank(addr1);
        return fairLaunch.registerProject(
            "Test Project",
            "A test project",
            "https://github.com/test/project",
            techStack,
            originalTeam,
            contributionWeights,
            roles,
            1000
        );
    }

    function _abandonProject() internal returns (uint256) {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        vm.warp(block.timestamp + GRACE_PERIOD + 1);
        
        vm.prank(addr3);
        fairLaunch.declareAbandoned(projectId, "Abandoned");
        
        return projectId;
    }

    function _setupRevivalProposal() internal returns (uint256 projectId, uint256 proposalId) {
        projectId = _abandonProject();
        
        vm.prank(addr3);
        proposalId = fairLaunch.submitRevivalProposal(
            projectId,
            newTeam,
            "Revival plan",
            milestones,
            10 ether,
            800
        );
    }

    function _setupRevivedProject() internal returns (uint256) {
        (uint256 projectId, uint256 proposalId) = _setupRevivalProposal();
        
        vm.prank(addr1);
        fairLaunch.voteOnProposal(proposalId, true);
        
        vm.prank(addr2);
        fairLaunch.voteOnProposal(proposalId, true);
        
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        fairLaunch.executeProposal(proposalId);
        
        return projectId;
    }
}

/*//////////////////////////////////////////////////////////////
                        MOCK ERC20 CONTRACT
//////////////////////////////////////////////////////////////*/

contract MockERC20 is Test {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}