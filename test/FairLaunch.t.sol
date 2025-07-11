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
        
        // Give accounts some ETH for testing
        vm.deal(addr1, 100 ether);
        vm.deal(addr2, 100 ether);
        vm.deal(addr3, 100 ether);
        vm.deal(addr4, 100 ether);
        vm.deal(addr5, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public {
        assertEq(fairLaunch.owner(), owner);
        assertEq(address(fairLaunch.fair3Token()), address(fair3Token));
        assertEq(fairLaunch.getTotalProjects(), 0);
        assertEq(fairLaunch.getTotalProposals(), 0);
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
        
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "A test project",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        uint256 projectId = fairLaunch.registerProject(params);
        
        assertEq(projectId, 1);
        assertEq(fairLaunch.getTotalProjects(), 1);
        
        FairLaunch.ProjectInfo memory info = fairLaunch.getProject(1);
        
        assertEq(info.name, "Test Project");
        assertEq(info.description, "A test project");
        assertEq(info.githubRepo, "https://github.com/test/project");
        assertEq(info.techStack.length, 2);
        assertEq(info.techStack[0], "Solidity");
        assertEq(info.techStack[1], "React");
        assertEq(info.originalTeam.length, 2);
        assertEq(info.originalTeam[0], addr1);
        assertEq(info.originalTeam[1], addr2);
        assertEq(info.royaltyRate, 1000);
        assertEq(uint256(info.status), 0); // ProjectStatus.Active
        assertEq(info.currentOwner, addr1);
        assertEq(info.abandonedTimestamp, 0);
        assertGt(info.lastActivityTimestamp, 0);
        
        // Check contributor details
        (uint256 weight1, string memory role1, bool isActive1) = fairLaunch.getContributor(1, addr1);
        assertEq(weight1, 6000);
        assertEq(role1, "Founder");
        assertEq(isActive1, true);
        
        (uint256 weight2, string memory role2, bool isActive2) = fairLaunch.getContributor(1, addr2);
        assertEq(weight2, 4000);
        assertEq(role2, "Developer");
        assertEq(isActive2, true);
    }

    function test_registerProjectRevertsWithEmptyName() public {
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "",
            description: "Description",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        vm.expectRevert("Name cannot be empty");
        fairLaunch.registerProject(params);
    }

    function test_registerProjectRevertsWithEmptyGithub() public {
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "Description",
            githubRepo: "",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        vm.expectRevert("GitHub repo required");
        fairLaunch.registerProject(params);
    }

    function test_registerProjectRevertsWithZeroTeamMember() public {
        address[] memory invalidTeam = new address[](2);
        invalidTeam[0] = address(0);
        invalidTeam[1] = addr2;
        
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "Description",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: invalidTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        vm.expectRevert("Team member address cannot be zero");
        fairLaunch.registerProject(params);
    }

    function test_registerProjectRevertsWithInvalidWeights() public {
        uint256[] memory invalidWeights = new uint256[](2);
        invalidWeights[0] = 5000;
        invalidWeights[1] = 4000; // Only 90%
        
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "Description",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: invalidWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        vm.expectRevert("Total contribution weights must equal 100%");
        fairLaunch.registerProject(params);
    }

    function test_registerProjectRevertsWithLowRoyaltyRate() public {
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "Description",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 400 // 4% - too low
        });
        
        vm.prank(addr1);
        vm.expectRevert("Invalid royalty rate");
        fairLaunch.registerProject(params);
    }

    function test_registerProjectRevertsWithHighRoyaltyRate() public {
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "Description", 
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 2000 // 20% - too high
        });
        
        vm.prank(addr1);
        vm.expectRevert("Invalid royalty rate");
        fairLaunch.registerProject(params);
    }

    function test_registerProjectRevertsWithDuplicateGithubRepo() public {
        string memory githubRepo = "https://github.com/test/project";
        
        FairLaunch.ProjectParams memory params1 = FairLaunch.ProjectParams({
            name: "Test Project 1",
            description: "Description",
            githubRepo: githubRepo,
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        fairLaunch.registerProject(params1);
        
        address[] memory newTeamMembers = new address[](2);
        newTeamMembers[0] = addr3;
        newTeamMembers[1] = addr4;
        
        FairLaunch.ProjectParams memory params2 = FairLaunch.ProjectParams({
            name: "Test Project 2",
            description: "Description",
            githubRepo: githubRepo, // Same repo
            techStack: techStack,
            team: newTeamMembers,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr2);
        vm.expectRevert("GitHub repo already registered");
        fairLaunch.registerProject(params2);
    }

    function test_registerProjectRevertsWithArrayLengthMismatch() public {
        uint256[] memory invalidWeights = new uint256[](1); // Wrong length
        invalidWeights[0] = 10000;
        
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "Description",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam, // Length 2
            contributionWeights: invalidWeights, // Length 1
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        vm.expectRevert("Team and weights length mismatch");
        fairLaunch.registerProject(params);
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
        
        FairLaunch.ProjectInfo memory info = fairLaunch.getProject(projectId);
        assertEq(uint256(info.status), 1); // ProjectStatus.Flagged
    }

    function test_flagProjectRevertsWithEmptyReason() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Reason required");
        fairLaunch.flagProject(projectId, "");
    }

    function test_flagProjectRevertsNonActiveProject() public {
        uint256 projectId = _registerTestProject();
        
        // Flag project first
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        // Try to flag again
        vm.prank(addr3);
        vm.expectRevert("Project not active");
        fairLaunch.flagProject(projectId, "Still no activity");
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
        
        FairLaunch.ProjectInfo memory info = fairLaunch.getProject(projectId);
        assertEq(uint256(info.status), 2); // ProjectStatus.Abandoned
    }

    function test_declareAbandonedRevertsBeforeGracePeriod() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        // Don't wait for grace period
        vm.prank(addr3);
        vm.expectRevert("Grace period not elapsed");
        fairLaunch.declareAbandoned(projectId, "Too early");
    }

    function test_declareAbandonedRevertsNotFlagged() public {
        uint256 projectId = _registerTestProject();
        
        vm.warp(block.timestamp + GRACE_PERIOD + 1);
        
        vm.prank(addr3);
        vm.expectRevert("Project must be flagged first");
        fairLaunch.declareAbandoned(projectId, "Not flagged");
    }

    function test_updateActivity() public {
        uint256 projectId = _registerTestProject();
        
        // Flag project
        vm.prank(addr3);
        fairLaunch.flagProject(projectId, "No activity");
        
        // Owner updates activity
        vm.prank(addr1);
        fairLaunch.updateActivity(projectId);
        
        FairLaunch.ProjectInfo memory info = fairLaunch.getProject(projectId);
        assertEq(uint256(info.status), 0); // ProjectStatus.Active
        assertEq(info.lastActivityTimestamp, block.timestamp);
    }

    function test_updateActivityRevertsNotOwner() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Not project owner");
        fairLaunch.updateActivity(projectId);
    }

    /*//////////////////////////////////////////////////////////////
                        REVIVAL PROPOSAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_submitRevivalProposal() public {
        uint256 projectId = _abandonProject();
        
        FairLaunch.ProposalParams memory params = FairLaunch.ProposalParams({
            projectId: projectId,
            newTeam: newTeam,
            revivalPlan: "We will revive this project with new features",
            milestones: milestones,
            requestedFunding: 10 ether,
            proposedRoyaltyRate: 800
        });
        
        vm.prank(addr3);
        vm.expectEmit(true, true, true, false);
        emit FairLaunch.RevivalProposalSubmitted(1, projectId, addr3);
        
        uint256 proposalId = fairLaunch.submitRevivalProposal(params);
        
        assertEq(proposalId, 1);
        assertEq(fairLaunch.getTotalProposals(), 1);
        
        FairLaunch.ProposalInfo memory info = fairLaunch.getRevivalProposal(1);
        
        assertEq(info.projectId, projectId);
        assertEq(info.proposer, addr3);
        assertEq(info.newTeam.length, 2);
        assertEq(info.newTeam[0], addr3);
        assertEq(info.newTeam[1], addr4);
        assertTrue(bytes(info.revivalPlan).length > 0);
        assertEq(info.milestones.length, 2);
        assertEq(info.milestones[0], "Milestone 1");
        assertEq(info.milestones[1], "Milestone 2");
        assertEq(info.requestedFunding, 10 ether);
        assertEq(info.proposedRoyaltyRate, 800);
        assertEq(info.votesFor, 0);
        assertEq(info.votesAgainst, 0);
        assertEq(uint256(info.status), 1); // ProposalStatus.Active
        
        // Check project status changed to InRevival
        FairLaunch.ProjectInfo memory projectInfo = fairLaunch.getProject(projectId);
        assertEq(uint256(projectInfo.status), 3); // ProjectStatus.InRevival
    }

    function test_submitRevivalProposalRevertsWithZeroAddress() public {
        uint256 projectId = _abandonProject();
        
        address[] memory invalidTeam = new address[](2);
        invalidTeam[0] = address(0);
        invalidTeam[1] = addr4;
        
        FairLaunch.ProposalParams memory params = FairLaunch.ProposalParams({
            projectId: projectId,
            newTeam: invalidTeam,
            revivalPlan: "Revival plan",
            milestones: milestones,
            requestedFunding: 10 ether,
            proposedRoyaltyRate: 800
        });
        
        vm.prank(addr3);
        vm.expectRevert("Team member address cannot be zero");
        fairLaunch.submitRevivalProposal(params);
    }

    function test_submitRevivalProposalRevertsWithInvalidRoyalty() public {
        uint256 projectId = _abandonProject();
        
        FairLaunch.ProposalParams memory params = FairLaunch.ProposalParams({
            projectId: projectId,
            newTeam: newTeam,
            revivalPlan: "Revival plan",
            milestones: milestones,
            requestedFunding: 10 ether,
            proposedRoyaltyRate: 300 // Too low
        });
        
        vm.prank(addr3);
        vm.expectRevert("Invalid royalty rate");
        fairLaunch.submitRevivalProposal(params);
    }

    function test_submitRevivalProposalRevertsEmptyTeam() public {
        uint256 projectId = _abandonProject();
        
        address[] memory emptyTeam = new address[](0);
        
        FairLaunch.ProposalParams memory params = FairLaunch.ProposalParams({
            projectId: projectId,
            newTeam: emptyTeam,
            revivalPlan: "Revival plan",
            milestones: milestones,
            requestedFunding: 10 ether,
            proposedRoyaltyRate: 800
        });
        
        vm.prank(addr3);
        vm.expectRevert("New team required");
        fairLaunch.submitRevivalProposal(params);
    }

    function test_submitRevivalProposalRevertsEmptyPlan() public {
        uint256 projectId = _abandonProject();
        
        FairLaunch.ProposalParams memory params = FairLaunch.ProposalParams({
            projectId: projectId,
            newTeam: newTeam,
            revivalPlan: "", // Empty plan
            milestones: milestones,
            requestedFunding: 10 ether,
            proposedRoyaltyRate: 800
        });
        
        vm.prank(addr3);
        vm.expectRevert("Revival plan required");
        fairLaunch.submitRevivalProposal(params);
    }

    /*//////////////////////////////////////////////////////////////
                            VOTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_voteOnProposal() public {
        (uint256 projectId, uint256 proposalId) = _setupRevivalProposal();
        
        uint256 expectedVotingPower = fairLaunch.getUserVotingPower(addr1);
        assertGt(expectedVotingPower, 0);
        
        vm.prank(addr1);
        vm.expectEmit(true, true, false, true);
        emit FairLaunch.VoteCast(proposalId, addr1, true, expectedVotingPower);
        
        fairLaunch.voteOnProposal(proposalId, true);
        
        FairLaunch.ProposalInfo memory info = fairLaunch.getRevivalProposal(proposalId);
        assertEq(info.votesFor, expectedVotingPower);
        assertEq(info.votesAgainst, 0);
    }

    function test_voteOnProposalAgainst() public {
        (, uint256 proposalId) = _setupRevivalProposal();
        
        uint256 expectedVotingPower = fairLaunch.getUserVotingPower(addr1);
        
        vm.prank(addr1);
        fairLaunch.voteOnProposal(proposalId, false);
        
        FairLaunch.ProposalInfo memory info = fairLaunch.getRevivalProposal(proposalId);
        assertEq(info.votesFor, 0);
        assertEq(info.votesAgainst, expectedVotingPower);
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

    function test_voteOnProposalRevertsAfterVotingPeriod() public {
        (, uint256 proposalId) = _setupRevivalProposal();
        
        // Wait for voting period to end
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        vm.prank(addr1);
        vm.expectRevert("Voting period ended");
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
        
        FairLaunch.ProjectInfo memory projectInfo = fairLaunch.getProject(projectId);
        assertEq(uint256(projectInfo.status), 4); // ProjectStatus.Revived
        assertEq(projectInfo.currentOwner, addr3);
        
        FairLaunch.ProposalInfo memory proposalInfo = fairLaunch.getRevivalProposal(proposalId);
        assertEq(uint256(proposalInfo.status), 2); // ProposalStatus.Approved
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
        
        FairLaunch.ProposalInfo memory proposalInfo = fairLaunch.getRevivalProposal(proposalId);
        assertEq(uint256(proposalInfo.status), 3); // ProposalStatus.Rejected
        
        FairLaunch.ProjectInfo memory projectInfo = fairLaunch.getProject(projectId);
        assertEq(uint256(projectInfo.status), 2); // ProjectStatus.Abandoned
    }

    function test_executeProposalRevertsBeforeVotingPeriod() public {
        (, uint256 proposalId) = _setupRevivalProposal();
        
        vm.prank(addr1);
        fairLaunch.voteOnProposal(proposalId, true);
        
        // Don't wait for voting period
        vm.expectRevert("Voting period not ended");
        fairLaunch.executeProposal(proposalId);
    }

    function test_executeProposalRevertsNoVotes() public {
        (, uint256 proposalId) = _setupRevivalProposal();
        
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        vm.expectRevert("No votes cast");
        fairLaunch.executeProposal(proposalId);
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

    function test_updateContributor() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr1);
        vm.expectEmit(true, true, false, true);
        emit FairLaunch.ContributorAdded(projectId, addr5, 1000);
        
        fairLaunch.updateContributor(projectId, addr5, 1000, "Tester", true);
        
        (uint256 weight, string memory role, bool isActive) = fairLaunch.getContributor(projectId, addr5);
        assertEq(weight, 1000);
        assertEq(role, "Tester");
        assertEq(isActive, true);
    }

    function test_updateContributorRevertsNotOwner() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr3);
        vm.expectRevert("Not project owner");
        fairLaunch.updateContributor(projectId, addr5, 1000, "Tester", true);
    }

    function test_updateContributorRevertsZeroAddress() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr1);
        vm.expectRevert("Contributor address cannot be zero");
        fairLaunch.updateContributor(projectId, address(0), 1000, "Tester", true);
    }

    function test_updateContributorRevertsEmptyRole() public {
        uint256 projectId = _registerTestProject();
        
        vm.prank(addr1);
        vm.expectRevert("Role cannot be empty");
        fairLaunch.updateContributor(projectId, addr5, 1000, "", true);
    }

    function test_setVotingPowerRevertsNotOwner() public {
        vm.prank(addr1);
        vm.expectRevert("Ownable: caller is not the owner");
        fairLaunch.setVotingPower(addr2, 1000);
    }

    function test_setVotingPower() public {
        fairLaunch.setVotingPower(addr2, 1000);
        
        uint256 votingPower = fairLaunch.getUserVotingPower(addr2);
        assertEq(votingPower, 1000 ether + 1000); // Token balance + reputation
    }

    function test_withdrawFeesRevertsNotOwner() public {
        vm.prank(addr1);
        vm.expectRevert("Ownable: caller is not the owner");
        fairLaunch.withdrawFees();
    }

    function test_withdrawFeesRevertsNoBalance() public {
        vm.expectRevert("No fees to withdraw");
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
        
        FairLaunch.ProjectInfo memory info = fairLaunch.getProject(projectId);
        assertEq(uint256(info.status), 5); // ProjectStatus.Disputed
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
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getUserVotingPowerZeroAddress() public {
        uint256 votingPower = fairLaunch.getUserVotingPower(address(0));
        assertEq(votingPower, 0);
    }

    function test_getUserProjectsEmptyArray() public {
        uint256[] memory userProjects = fairLaunch.getUserProjects(addr5);
        assertEq(userProjects.length, 0);
    }

    function test_projectExistsModifier() public {
        vm.expectRevert("Project does not exist");
        fairLaunch.getProject(999);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _registerTestProject() internal returns (uint256) {
        FairLaunch.ProjectParams memory params = FairLaunch.ProjectParams({
            name: "Test Project",
            description: "A test project",
            githubRepo: "https://github.com/test/project",
            techStack: techStack,
            team: originalTeam,
            contributionWeights: contributionWeights,
            roles: roles,
            royaltyRate: 1000
        });
        
        vm.prank(addr1);
        return fairLaunch.registerProject(params);
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
        
        FairLaunch.ProposalParams memory params = FairLaunch.ProposalParams({
            projectId: projectId,
            newTeam: newTeam,
            revivalPlan: "Revival plan",
            milestones: milestones,
            requestedFunding: 10 ether,
            proposedRoyaltyRate: 800
        });
        
        vm.prank(addr3);
        proposalId = fairLaunch.submitRevivalProposal(params);
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