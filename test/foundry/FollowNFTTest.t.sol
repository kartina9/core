// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'test/foundry/base/BaseTest.t.sol';
import 'test/foundry/ERC721Test.t.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IFollowNFT} from 'contracts/interfaces/IFollowNFT.sol';
import {FollowNFT} from 'contracts/FollowNFT.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';

contract FollowNFTTest is BaseTest, ERC721Test {
    uint256 constant MINT_NEW_TOKEN = 0;
    address targetProfileOwner;
    uint256 targetProfileId;
    address followerProfileOwner;
    uint256 followerProfileId;
    address alreadyFollowingProfileOwner;
    uint256 alreadyFollowingProfileId;
    address targetFollowNFT;
    uint256 lastAssignedTokenId;
    address followHolder;

    function setUp() public override {
        super.setUp();

        targetProfileOwner = address(0xC0FFEE);
        targetProfileId = _createProfile(targetProfileOwner);
        followerProfileOwner = me;
        followerProfileId = _createProfile(followerProfileOwner);

        followHolder = address(0xF0110111401DE2);

        alreadyFollowingProfileOwner = address(0xF01108);
        alreadyFollowingProfileId = _createProfile(alreadyFollowingProfileOwner);
        lastAssignedTokenId = _follow(alreadyFollowingProfileOwner, alreadyFollowingProfileId, targetProfileId, 0, '')[
            0
        ];

        targetFollowNFT = hub.getFollowNFT(targetProfileId);
        followNFT = FollowNFT(targetFollowNFT);
    }

    function _mintERC721(address to) internal virtual override returns (uint256) {
        uint256 tokenId = _follow(to, _createProfile(to), targetProfileId, 0, '')[0];
        vm.prank(to);
        followNFT.wrap(tokenId);
        return tokenId;
    }

    function _burnERC721(uint256 tokenId) internal virtual override {
        return followNFT.burn(tokenId);
    }

    function _getERC721TokenAddress() internal view virtual override returns (address) {
        return targetFollowNFT;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////
    // Follow - General - Negatives
    //////////////////////////////////////////////////////////

    function testCannotCallFollowIfNotTheHub(address sender) public {
        vm.assume(sender != address(hub));
        vm.assume(sender != address(0));

        vm.prank(sender);

        vm.expectRevert(Errors.NotHub.selector);
        followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });
    }

    function testCannotFollowIfAlreadyFollowing() public {
        vm.prank(address(hub));

        vm.expectRevert(IFollowNFT.AlreadyFollowing.selector);
        followNFT.follow({
            followerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });
    }

    function testCannotFollowWithTokenIfTheTokenDoesNotExist(uint256 unexistentTokenId) public {
        vm.assume(unexistentTokenId != MINT_NEW_TOKEN);
        vm.assume(followNFT.getFollowerProfileId(unexistentTokenId) == 0);
        vm.assume(!followNFT.exists(unexistentTokenId));
        vm.assume(followNFT.getProfileIdAllowedToRecover(unexistentTokenId) == 0);

        vm.prank(address(hub));

        vm.expectRevert(IFollowNFT.FollowTokenDoesNotExist.selector);

        followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: unexistentTokenId
        });
    }

    //////////////////////////////////////////////////////////
    // Follow - Minting new token - Negatives
    //////////////////////////////////////////////////////////

    // No negatives when minting a new token, all the failing cases will occur at LensHub level. See `FollowTest.t.sol`.

    //////////////////////////////////////////////////////////
    // Follow - Minting new token - Scenarios
    //////////////////////////////////////////////////////////

    function testNewMintedTokenIdIsLastAssignedPlusOne() public {
        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });

        assertEq(assignedTokenId, lastAssignedTokenId + 1);
    }

    function testFollowingMintingNewTokenSetsFollowerStatusCorrectly() public {
        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });

        bool isFollowing = followNFT.isFollowing(followerProfileId);
        assertEq(isFollowing, true);

        uint256 followerProfileIdSet = followNFT.getFollowerProfileId(assignedTokenId);
        assertEq(followerProfileIdSet, followerProfileId);

        uint256 followIdByFollower = followNFT.getFollowTokenId(followerProfileId);
        assertEq(followIdByFollower, assignedTokenId);
    }

    function testExpectedFollowDataAfterMintingNewToken() public {
        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });

        Types.FollowData memory followData = followNFT.getFollowData(assignedTokenId);

        assertEq(followData.followerProfileId, followerProfileId);
        assertEq(followData.originalFollowTimestamp, block.timestamp);
        assertEq(followData.followTimestamp, block.timestamp);
        assertEq(followData.profileIdAllowedToRecover, 0);
    }

    function testFollowTokenIsByDefaultUnwrapped() public {
        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });

        assertTrue(followNFT.isFollowing(followerProfileId));

        vm.expectRevert(Errors.TokenDoesNotExist.selector);
        followNFT.ownerOf(assignedTokenId);
    }

    //////////////////////////////////////////////////////////
    // Follow - With unwrapped token - Scenarios
    //////////////////////////////////////////////////////////

    function testFollowWithUnwrappedTokenWhenCurrentFollowerWasBurnedAndTransactionExecutorIsFollowerOwner() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        hub.burn(alreadyFollowingProfileId);
        assertFalse(hub.exists(alreadyFollowingProfileId));

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }

    function testFollowWithUnwrappedTokenWhenCurrentFollowerWasBurnedAndTransactionExecutorIsApprovedDelegatee(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != followerProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        hub.burn(alreadyFollowingProfileId);
        assertFalse(hub.exists(alreadyFollowingProfileId));

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: executorAsApprovedDelegatee,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }

    //////////////////////////////////////////////////////////
    // Follow - With wrapped token - Scenarios
    //////////////////////////////////////////////////////////

    function testFollowWithWrappedTokenWhenFollowerOwnerOwnsFollowTokenAndIsActingAsTransactionExecutor() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followerProfileOwner, followTokenId);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
    }

    function testFollowWithWrappedTokenWhenFollowerOwnerAlsoOwnsFollowTokenAndTransactionExecutorIsApprovedDelegatee(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != followerProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followerProfileOwner, followTokenId);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: executorAsApprovedDelegatee,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
    }

    function testFollowWithWrappedTokenWhenExecutorOwnsFollowTokenAndTransactionExecutorIsApprovedDelegatee(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != followerProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, executorAsApprovedDelegatee, followTokenId);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: executorAsApprovedDelegatee,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
    }

    function testFollowWithWrappedTokenWhenExecutorIsApprovedForAllAndTransactionExecutorIsFollowerOwner() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.setApprovalForAll(followerProfileOwner, true);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
    }

    function testFollowWithWrappedTokenWhenExecutorIsApprovedForAllAndTransactionExecutorIsApprovedDelegatee(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != followerProfileOwner);
        vm.assume(executorAsApprovedDelegatee != alreadyFollowingProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.setApprovalForAll(executorAsApprovedDelegatee, true);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: executorAsApprovedDelegatee,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
    }

    function testFollowWithWrappedTokenWhenProfileIsApprovedToFollowAndTransactionExecutorIsFollowerOwner() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);
        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }

    function testFollowWithWrappedTokenWhenProfileIsApprovedToFollowAndTransactionExecutorIsApprovedDelegatee(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != followerProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);
        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: executorAsApprovedDelegatee,
            followTokenId: followTokenId
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(followerProfileId), followTokenId);
        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }

    //////////////////////////////////////////////////////////
    // Follow - Recovering token - Scenarios
    //////////////////////////////////////////////////////////

    function testFollowRecoveringToken() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));

        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner,
            followTokenId: followTokenId
        });

        assertTrue(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(assignedTokenId, followTokenId);
        assertEq(followNFT.getFollowTokenId(alreadyFollowingProfileId), followTokenId);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////
    // Unfollow - Negatives
    //////////////////////////////////////////////////////////

    function testCannotCallUnfollowIfNotTheHub(address sender) public {
        vm.assume(sender != address(hub));
        vm.assume(sender != address(0));

        vm.prank(sender);

        vm.expectRevert(Errors.NotHub.selector);
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });
    }

    function testCannotUnfollowIfNotAlreadyFollowing() public {
        assertFalse(followNFT.isFollowing(followerProfileId));

        vm.prank(address(hub));

        vm.expectRevert(IFollowNFT.NotFollowing.selector);
        followNFT.unfollow({unfollowerProfileId: followerProfileId, transactionExecutor: followerProfileOwner});
    }

    function testCannotUnfollowIfTokenIsWrappedAndUnfollowerOwnerOrTransactionExecutorDontHoldTheTokenOrApprovedForAll(
        address unrelatedAddress
    ) public {
        vm.assume(unrelatedAddress != address(0));
        vm.assume(unrelatedAddress != alreadyFollowingProfileOwner);
        vm.assume(!hub.isDelegatedExecutorApproved(alreadyFollowingProfileId, unrelatedAddress));
        vm.assume(!followNFT.isApprovedForAll(alreadyFollowingProfileOwner, unrelatedAddress));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, unrelatedAddress, followTokenId);

        vm.prank(address(hub));

        vm.expectRevert(IFollowNFT.DoesNotHavePermissions.selector);
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });
    }

    function testCannotRemoveFollowerOnWrappedIfNotHolder(address unrelatedAddress) public {
        vm.assume(unrelatedAddress != address(0));
        vm.assume(unrelatedAddress != followHolder);

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followHolder, followTokenId);

        vm.prank(unrelatedAddress);

        vm.expectRevert(IFollowNFT.DoesNotHavePermissions.selector);
        followNFT.removeFollower({followTokenId: followTokenId});
    }

    //////////////////////////////////////////////////////////
    // Unfollow - Scenarios
    //////////////////////////////////////////////////////////

    function testUnfollowAsFollowerProfileOwnerWhenTokenIsWrapped() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(address(hub));

        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getFollowerProfileId(alreadyFollowingProfileId), 0);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    function testUnfollowAsApprovedDelegatedExecutorOfFollowerOwnerWhenTokenIsWrapped(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != alreadyFollowingProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(address(hub));

        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: executorAsApprovedDelegatee
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getFollowerProfileId(alreadyFollowingProfileId), 0);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    function testUnfollowAsFollowTokenOwnerWhenTokenIsWrapped(address followTokenOwner) public {
        vm.assume(followTokenOwner != alreadyFollowingProfileOwner);
        vm.assume(followTokenOwner != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followTokenOwner, followTokenId);

        vm.prank(address(hub));

        followNFT.unfollow({unfollowerProfileId: alreadyFollowingProfileId, transactionExecutor: followTokenOwner});

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getFollowerProfileId(alreadyFollowingProfileId), 0);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    function testUnfollowAsApprovedForAllByTokenOwnerWhenTokenIsWrapped(address approvedForAll) public {
        vm.assume(approvedForAll != alreadyFollowingProfileOwner);
        vm.assume(approvedForAll != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.setApprovalForAll(approvedForAll, true);

        vm.prank(address(hub));

        followNFT.unfollow({unfollowerProfileId: alreadyFollowingProfileId, transactionExecutor: approvedForAll});

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getFollowerProfileId(alreadyFollowingProfileId), 0);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    function testUnfollowAsFollowerProfileOwnerWhenTokenIsUnwrapped() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));

        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getFollowerProfileId(alreadyFollowingProfileId), 0);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);
    }

    function testUnfollowAsApprovedDelegatedExecutorOfFollowerOwnerWhenTokenIsUnwrapped(
        address executorAsApprovedDelegatee
    ) public {
        vm.assume(executorAsApprovedDelegatee != alreadyFollowingProfileOwner);
        vm.assume(executorAsApprovedDelegatee != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));

        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: executorAsApprovedDelegatee
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.getFollowerProfileId(alreadyFollowingProfileId), 0);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);
    }

    function testRemoveFollower() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followHolder, followTokenId);

        vm.prank(followHolder);
        followNFT.removeFollower({followTokenId: followTokenId});

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////
    // Wrap - Negatives
    //////////////////////////////////////////////////////////

    function testCannotWrapIfAlreadyWrapped() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);

        vm.expectRevert(IFollowNFT.AlreadyWrapped.selector);
        followNFT.wrap(followTokenId);
    }

    function testCannotWrapIfTokenDoesNotExist(uint256 unexistentTokenId) public {
        vm.assume(followNFT.getFollowerProfileId(unexistentTokenId) == 0);
        vm.assume(!followNFT.exists(unexistentTokenId));

        vm.expectRevert(IFollowNFT.FollowTokenDoesNotExist.selector);
        followNFT.wrap(unexistentTokenId);
    }

    function testCannotWrapIfSenderIsNotFollowerOwner(address notFollowerOwner) public {
        vm.assume(notFollowerOwner != alreadyFollowingProfileOwner);
        vm.assume(notFollowerOwner != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(notFollowerOwner);

        vm.expectRevert(IFollowNFT.DoesNotHavePermissions.selector);
        followNFT.wrap(followTokenId);
    }

    function testCannotWrapRecoveringWhenTheProfileAllowedToRecoverDoesNotExistAnymore() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        hub.burn(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        vm.expectRevert(Errors.TokenDoesNotExist.selector);
        followNFT.wrap(followTokenId);
    }

    function testCannotWrapRecoveringWhenTheSenderDoesNotOwnTheProfileAllowedToRecover(
        address unrelatedAddress
    ) public {
        vm.assume(unrelatedAddress != address(0));
        vm.assume(unrelatedAddress != alreadyFollowingProfileOwner);

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        hub.transferFrom({
            from: alreadyFollowingProfileOwner,
            to: unrelatedAddress,
            tokenId: alreadyFollowingProfileId
        });

        vm.prank(alreadyFollowingProfileOwner);
        vm.expectRevert(IFollowNFT.DoesNotHavePermissions.selector);
        followNFT.wrap(followTokenId);
    }

    //////////////////////////////////////////////////////////
    // Wrap - Scenarios
    //////////////////////////////////////////////////////////

    function testWrappedTokenOwnerIsFollowerProfileOwnerAfterUntyingAndWrapping() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        assertEq(followNFT.ownerOf(followTokenId), alreadyFollowingProfileOwner);
    }

    function testWrappedTokenStillHeldByPreviousFollowerOwnerAfterAFollowerProfileTransfer(
        address newFollowerProfileOwner
    ) public {
        vm.assume(newFollowerProfileOwner != followerProfileOwner);
        vm.assume(newFollowerProfileOwner != address(0));

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });

        vm.prank(followerProfileOwner);
        followNFT.wrap(assignedTokenId);

        assertEq(followNFT.ownerOf(assignedTokenId), followerProfileOwner);

        assertTrue(followNFT.isFollowing(followerProfileId));
        uint256 followerProfileIdSet = followNFT.getFollowerProfileId(assignedTokenId);
        assertEq(followerProfileIdSet, followerProfileId);

        vm.prank(followerProfileOwner);
        hub.transferFrom(followerProfileOwner, newFollowerProfileOwner, followerProfileId);

        assertEq(hub.ownerOf(followerProfileId), newFollowerProfileOwner);
        assertEq(followNFT.ownerOf(assignedTokenId), followerProfileOwner);

        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(followerProfileIdSet, followNFT.getFollowerProfileId(assignedTokenId));
    }

    function testRecoveringTokenThroughWrappingIt() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        assertEq(followNFT.ownerOf(followTokenId), alreadyFollowingProfileOwner);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    function testRecoveringTokenThroughWrappingItAfterProfileAllowedToRecoverWasTransferred(
        address unrelatedAddress
    ) public {
        vm.assume(unrelatedAddress != address(0));
        vm.assume(unrelatedAddress != alreadyFollowingProfileOwner);

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(address(hub));
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        hub.transferFrom({
            from: alreadyFollowingProfileOwner,
            to: unrelatedAddress,
            tokenId: alreadyFollowingProfileId
        });

        vm.prank(unrelatedAddress);
        followNFT.wrap(followTokenId);

        assertEq(followNFT.ownerOf(followTokenId), unrelatedAddress);
        assertEq(followNFT.getProfileIdAllowedToRecover(followTokenId), 0);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////
    // Unwrap - Negatives
    //////////////////////////////////////////////////////////

    function testCannotUnwrapIfTokenDoesNotHaveAFollowerSet() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(address(hub));
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        vm.expectRevert(IFollowNFT.NotFollowing.selector);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.unwrap(followTokenId);
    }

    function testCannotUnwrapIfTokenIsAlreadyUnwrapped() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.expectRevert(Errors.TokenDoesNotExist.selector);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.unwrap(followTokenId);
    }

    function testCannotUnwrapIfSenderIsNotTokenOwnerOrApprovedOrApprovedForAll(address sender) public {
        // You can't approve a token that is not wrapped, so no need to check for `followNFT.getApproved(followTokenId)`
        vm.assume(sender != alreadyFollowingProfileOwner);
        vm.assume(sender != address(0));
        vm.assume(!followNFT.isApprovedForAll(alreadyFollowingProfileOwner, sender));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.expectRevert(Errors.NotOwnerOrApproved.selector);
        vm.prank(sender);
        followNFT.unwrap(followTokenId);
    }

    //////////////////////////////////////////////////////////
    // Unwrap - Scenarios
    //////////////////////////////////////////////////////////

    function testTokenOwnerCanUnwrapIt() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.unwrap(followTokenId);

        assertFalse(followNFT.exists(followTokenId));
    }

    function testApprovedForAllCanUnwrapAToken(address approvedForAll) public {
        vm.assume(approvedForAll != alreadyFollowingProfileOwner);
        vm.assume(approvedForAll != address(0));

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.setApprovalForAll(approvedForAll, true);

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(approvedForAll);
        followNFT.unwrap(followTokenId);

        assertFalse(followNFT.exists(followTokenId));
    }

    function testApprovedForATokenCanUnwrapIt(address approved) public {
        vm.assume(approved != alreadyFollowingProfileOwner);
        vm.assume(approved != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approve(approved, followTokenId);

        vm.prank(approved);
        followNFT.unwrap(followTokenId);

        assertFalse(followNFT.exists(followTokenId));
    }

    function testUnwrappedTokenStillTiedToFollowerProfileAfterAFollowerProfileTransfer(
        address newFollowerProfileOwner
    ) public {
        vm.assume(newFollowerProfileOwner != followerProfileOwner);
        vm.assume(newFollowerProfileOwner != address(0));

        vm.prank(address(hub));

        uint256 assignedTokenId = followNFT.follow({
            followerProfileId: followerProfileId,
            transactionExecutor: followerProfileOwner,
            followTokenId: MINT_NEW_TOKEN
        });

        assertTrue(followNFT.isFollowing(followerProfileId));
        uint256 followerProfileIdSet = followNFT.getFollowerProfileId(assignedTokenId);
        assertEq(followerProfileIdSet, followerProfileId);

        vm.prank(followerProfileOwner);
        hub.transferFrom(followerProfileOwner, newFollowerProfileOwner, followerProfileId);

        assertEq(hub.ownerOf(followerProfileId), newFollowerProfileOwner);

        assertTrue(followNFT.isFollowing(followerProfileId));
        assertEq(followerProfileIdSet, followNFT.getFollowerProfileId(assignedTokenId));

        vm.prank(newFollowerProfileOwner);
        followNFT.wrap(assignedTokenId);
        assertEq(followNFT.ownerOf(assignedTokenId), newFollowerProfileOwner);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////
    // Block - Negatives
    //////////////////////////////////////////////////////////

    function testCannotCallBlockIfNotTheHub(address sender) public {
        vm.assume(sender != address(hub));
        vm.assume(sender != address(0));

        vm.prank(sender);

        vm.expectRevert(Errors.NotHub.selector);
        followNFT.processBlock(followerProfileId);
    }

    //////////////////////////////////////////////////////////
    // Block - Scenarios
    //////////////////////////////////////////////////////////

    function testCanBlockSomeoneAlreadyBlocked() public {
        vm.prank(address(hub));
        followNFT.processBlock(followerProfileId);

        vm.prank(address(hub));
        followNFT.processBlock(followerProfileId);
    }

    function testBlockingFollowerThatWasFollowingWithWrappedTokenMakesHimUnfollowButKeepsTheWrappedToken() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        assertTrue(followNFT.isFollowing(alreadyFollowingProfileId));

        vm.prank(address(hub));
        followNFT.processBlock(alreadyFollowingProfileId);

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));

        assertEq(followNFT.ownerOf(followTokenId), alreadyFollowingProfileOwner);
    }

    function testBlockingFollowerThatWasFollowingWithUnwrappedFirstWrapsTokenAndThenMakesHimUnfollowKeepingItWrapped()
        public
    {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        assertFalse(followNFT.exists(followTokenId));
        assertTrue(followNFT.isFollowing(alreadyFollowingProfileId));

        vm.prank(address(hub));
        followNFT.processBlock(alreadyFollowingProfileId);

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.ownerOf(followTokenId), alreadyFollowingProfileOwner);
    }

    function testBlockingProfileThatWasNotFollowingButItsOwnerHoldsWrappedFollowTokenDoesNotChangeAnything() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(address(hub));
        followNFT.unfollow({
            unfollowerProfileId: alreadyFollowingProfileId,
            transactionExecutor: alreadyFollowingProfileOwner
        });

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.ownerOf(followTokenId), alreadyFollowingProfileOwner);

        vm.prank(address(hub));
        followNFT.processBlock(alreadyFollowingProfileId);

        assertFalse(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.ownerOf(followTokenId), alreadyFollowingProfileOwner);
    }

    function testBlockingProfileThatWasNotFollowingButItsOwnerHoldsWrappedFollowTokenWithFollowerDoesNotChangeAnything()
        public
    {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followerProfileOwner, followTokenId);

        assertTrue(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.ownerOf(followTokenId), followerProfileOwner);

        vm.prank(address(hub));
        followNFT.processBlock(followerProfileId);

        assertTrue(followNFT.isFollowing(alreadyFollowingProfileId));
        assertEq(followNFT.ownerOf(followTokenId), followerProfileOwner);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////
    // Approve follow - Negatives
    //////////////////////////////////////////////////////////

    function testCannotApproveFollowForUnexistentProfile(uint256 unexistentProfileId) public {
        vm.assume(!hub.exists(unexistentProfileId));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.expectRevert(Errors.TokenDoesNotExist.selector);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(unexistentProfileId, followTokenId);
    }

    function testCannotApproveFollowForUnexistentFollowToken(uint256 unexistentFollowTokenId) public {
        vm.assume(!followNFT.exists(unexistentFollowTokenId));
        vm.assume(followNFT.getFollowerProfileId(unexistentFollowTokenId) == 0);

        vm.expectRevert(IFollowNFT.OnlyWrappedFollowTokens.selector);
        followNFT.approveFollow(followerProfileId, unexistentFollowTokenId);
    }

    function testCannotApproveFollowForWrappedTokenIfCallerIsNotItsOwnerOrApprovedForAllByHim(address sender) public {
        vm.assume(sender != alreadyFollowingProfileOwner);
        vm.assume(!followNFT.isApprovedForAll(alreadyFollowingProfileOwner, sender));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.expectRevert(IFollowNFT.DoesNotHavePermissions.selector);
        vm.prank(sender);
        followNFT.approveFollow(followerProfileId, followTokenId);
    }

    function testCannotApproveFollowIfTokenIsUnwrapped() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.expectRevert(IFollowNFT.OnlyWrappedFollowTokens.selector);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);
    }

    //////////////////////////////////////////////////////////
    // Approve follow - Scenarios
    //////////////////////////////////////////////////////////

    function testApproveFollowWhenTokenIsWrappedAndCallerIsItsOwner() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);
    }

    function testApproveFollowWhenTokenIsWrappedAndCallerIsApprovedForAllByItsOwner(address approvedForAll) public {
        vm.assume(approvedForAll != alreadyFollowingProfileOwner);
        vm.assume(approvedForAll != address(0));

        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);
        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.setApprovalForAll(approvedForAll, true);

        vm.prank(approvedForAll);
        followNFT.approveFollow(followerProfileId, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);
    }

    function testFollowApprovalIsClearedAfterUnwrapping() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.unwrap(followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), 0);

        // Wraps again and checks that it keeps being clear.

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }

    function testFollowApprovalIsClearedAfterTransfer() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.transferFrom(alreadyFollowingProfileOwner, followerProfileOwner, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), 0);

        // Transfers back to the previous owner and checks that it keeps being clear.

        vm.prank(followerProfileOwner);
        followNFT.transferFrom(followerProfileOwner, alreadyFollowingProfileOwner, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }

    function testFollowApprovalIsClearedAfterBurning() public {
        uint256 followTokenId = followNFT.getFollowTokenId(alreadyFollowingProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.wrap(followTokenId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.approveFollow(followerProfileId, followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), followerProfileId);

        vm.prank(alreadyFollowingProfileOwner);
        followNFT.burn(followTokenId);

        assertEq(followNFT.getFollowApproved(followTokenId), 0);
    }
}