// SPDX-License-Identifier: MIT
// Creator: Amar
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Stake is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Interfaces for ERC20 and ERC721
    IERC20 public immutable rewardsToken;
    IERC721 public immutable nftCollection;

    uint mintimeperiod = 1 days;
    uint maxtimeperiod = 90 days;
    uint max_rewards_perNFT; // deciding the rewards_per_nft based on (rewards_per_day* max_time(day))
    uint rewardsPerDay;

    event stake_status(
        address indexed owner,
        uint stake_time,
        uint indexed nft_id
    );

    event withdraw_status(
        address indexed owner,
        uint indexed nft_id,
        uint nft_withdrawn_time,
        uint current_rewards
    );
    event rewards_status(
        address indexed staker,
        uint timeofclaim,
        uint NFTs_staked,
        uint clamed_rewards
    );

    struct tokendetails {
        address owner;
        uint staketime;
        uint present_rewards; //rewards staked till date
        uint claimable_rewards;
        uint timeOfLastUpdate;
    }
    // Details of the respective token
    mapping(uint => tokendetails) internal stakeIDs;
    // user info of the staked tokens
    mapping(address => uint[]) internal usersNFT;

    constructor(
        IERC721 _nftCollection,
        IERC20 _rewardsToken,
        uint rewardsperday,
        uint max_rewards_per_nft
    ) {
        nftCollection = _nftCollection;
        rewardsToken = _rewardsToken;
        rewardsPerDay = rewardsperday;
        max_rewards_perNFT = max_rewards_per_nft;
    }

    // NFT staking function
    function stake(uint _tokenId) external nonReentrant {
        require(
            nftCollection.ownerOf(_tokenId) == msg.sender,
            "Can't stake tokens you don't own!"
        );

        nftCollection.transferFrom(msg.sender, address(this), _tokenId);

        usersNFT[msg.sender].push(_tokenId);

        stakeIDs[_tokenId] = tokendetails(msg.sender, block.timestamp, 0, 0, 0);

        emit stake_status(msg.sender, block.timestamp, _tokenId);
    }

    // withdrawing the Nft from the contract
    function withdraw(uint _tokenId) external nonReentrant {
        require(
            stakeIDs[_tokenId].owner == msg.sender,
            "withdrawer is not the owner of the NFTs"
        );
        require(
            (block.timestamp - stakeIDs[_tokenId].staketime) >= mintimeperiod,
            "The NFT should be staked atleast for a day"
        );

        calculateRewards(_tokenId);

        nftCollection.transferFrom(address(this), msg.sender, _tokenId);

        rewardsToken.safeTransfer(
            msg.sender,
            stakeIDs[_tokenId].claimable_rewards
        );

        uint[] storage total_tokens = usersNFT[msg.sender];
        for (uint i; i < total_tokens.length; i++) {
            if (total_tokens[i] == _tokenId) {
                total_tokens[i] = total_tokens[total_tokens.length - 1];
                total_tokens.pop();
                break;
            }
        }

        emit withdraw_status(
            msg.sender,
            _tokenId,
            block.timestamp,
            stakeIDs[_tokenId].claimable_rewards
        );
        delete stakeIDs[_tokenId];
    }

    //  claiming rewards for the staked NFTs
    function claimRewards() external nonReentrant {
        uint[] memory tokens = usersNFT[msg.sender];
        uint rewards;

        for (uint i; i < tokens.length; i++) {
            calculateRewards(tokens[i]);
            rewards += stakeIDs[tokens[i]].claimable_rewards;
            stakeIDs[tokens[i]].timeOfLastUpdate = block.timestamp;
            stakeIDs[tokens[i]].claimable_rewards = 0;
        }
        require(rewards > 0, "You have no rewards to claim");
        rewardsToken.safeTransfer(msg.sender, rewards);

        emit rewards_status(
            msg.sender,
            block.timestamp,
            tokens.length,
            rewards
        );
    }

    //////////
    // View //
    //////////

    // Getting the owner address if nft staked
    // used for marketplace contract
    function StakeInfo(uint tokenID) external view returns (address) {
        address token_user = stakeIDs[tokenID].owner;
        return token_user;
    }
    
    // Get stake time of nft
    function stakeTime(uint tokenId) external view returns(uint) {
        return stakeIDs[tokenId].staketime;
    }

    // To know the rewards for the staked NFTs
    function availableRewards() external view returns(uint) {
        uint[] memory tokens = usersNFT[msg.sender];
        uint _rewards;
        for (uint i; i < tokens.length; i++) {
            if (stakeIDs[tokens[i]].timeOfLastUpdate == 0) {
                if (
                    block.timestamp - stakeIDs[tokens[i]].staketime < maxtimeperiod
                ) {
                    uint rewards = (((
                        uint(block.timestamp - stakeIDs[tokens[i]].staketime)
                    ) / uint(86400)) * rewardsPerDay);
                    _rewards += rewards;
                } else {
                    _rewards += max_rewards_perNFT;
                }

            } else {
                if (
                    block.timestamp - stakeIDs[tokens[i]].staketime >=
                    maxtimeperiod
                ) {
                    _rewards +=
                        max_rewards_perNFT -
                        stakeIDs[tokens[i]].present_rewards;
                } else {
                    uint rewards = (((
                        uint(
                            block.timestamp -
                                stakeIDs[tokens[i]].timeOfLastUpdate
                        )
                    ) / uint(86400)) * rewardsPerDay);
                    _rewards += rewards;
                }
            }
        }
        return _rewards;
    }

    /////////////
    // Internal//
    /////////////

    // Calculate rewards for param _staker by calculating the time passed
    // since last update in Days and mulitplying it to ERC721 Tokens Staked
    // and rewardsPerDay.


    function calculateRewards(uint _tokenId) internal {
        if (stakeIDs[_tokenId].timeOfLastUpdate == 0) {
            if (
                block.timestamp - stakeIDs[_tokenId].staketime < maxtimeperiod
            ) {
                uint rewards = (((
                    uint(block.timestamp - stakeIDs[_tokenId].staketime)
                ) / uint(86400)) * rewardsPerDay);
                stakeIDs[_tokenId].present_rewards = rewards;
                stakeIDs[_tokenId].claimable_rewards = rewards;
            } else {
                stakeIDs[_tokenId].present_rewards = max_rewards_perNFT;
                stakeIDs[_tokenId].claimable_rewards = max_rewards_perNFT;
            }

        } else {
            if (
                block.timestamp - stakeIDs[_tokenId].staketime >= maxtimeperiod
            ) {
                stakeIDs[_tokenId].claimable_rewards =
                    max_rewards_perNFT -
                    stakeIDs[_tokenId].present_rewards;
                stakeIDs[_tokenId].present_rewards = max_rewards_perNFT;
            } else {
                uint rewards = (((
                    uint(
                        block.timestamp - stakeIDs[_tokenId].timeOfLastUpdate
                    )
                ) / uint(86400)) * rewardsPerDay);

                stakeIDs[_tokenId].claimable_rewards = rewards;
                stakeIDs[_tokenId].present_rewards += rewards;
            }
        }
    }
}
