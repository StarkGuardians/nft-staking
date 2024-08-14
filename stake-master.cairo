// SPDX-License-Identifier: Not licensed
// OpenZeppelin Contracts for Cairo v0.7.0 (token/erc721/erc721.cairo)

// When `LegacyMap` is called with a non-existent key, it returns a struct with all properties are initialized to zero values.

use starknet::ContractAddress;
use starknet::contract_address_const;
use openzeppelin::token::erc721::interface::IERC721CamelOnlyDispatcher;


#[starknet::interface]
trait IERC721CamelCase<TState> {
    fn safe_transfer_from(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data_len: felt252,
        data: Span<felt252>
    );
    fn safeTransferFrom(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        tokenId: u256,
        data_len: felt252,
        data: Span<felt252>
    );
    fn transferFrom(ref self: TState, from: ContractAddress, to: ContractAddress, tokenId: u256);
}

fn sgn_contract() -> IERC721CamelCaseDispatcher {
    IERC721CamelCaseDispatcher {
        contract_address: contract_address_const::<
            0x2d679a171589777bc996fb27767ff9a2e44c7e07967760dea3df31704ab398a
        >(),
    }
}

#[starknet::contract]
mod ChefGuardian {
    use core::traits::DivEq;
    use core::num::traits::zero::Zero;
    use core::fmt::Display;
    use core::fmt::Debug;
    use core::array::SpanTrait;
    use super::{sgn_contract};
    use super::IERC721CamelCaseDispatcherTrait;
    use core::bool;
    use core::array::ArrayTrait;
    use core::Zeroable;
    use core::clone::Clone;
    use core::option::OptionTrait;
    use core::traits::{Destruct, TryInto, Into,};
    use integer::{u256_from_felt252, U64IntoFelt252};
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, get_contract_address,
        contract_address_const, class_hash::ClassHash
    };
    use openzeppelin::{
        upgrades::UpgradeableComponent, upgrades::interface::IUpgradeable,
        introspection::src5::SRC5Component, introspection::interface::ISRC5,
        security::ReentrancyGuardComponent, access::ownable::OwnableComponent,
        access::ownable::interface::IOwnable, token::erc721::interface::IERC721ReceiverCamel,
        token::erc721::ERC721ReceiverComponent
    };

    use sgn_stake_master::interface::IChefGuardian::{
        UserLeaderboardStruct, DepositInfo, IChefGuardian, UserActiveDeposit
    };

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy, event: ReentrancyEvent);
    component!(path: ERC721ReceiverComponent, storage: erc721Receiver, event: Erc721ReceiverEvent);


    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5CamelImpl = SRC5Component::SRC5CamelImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ReceiverImpl =
        ERC721ReceiverComponent::ERC721ReceiverImpl<ContractState>;
    impl ERC721ReceiverInternalImpl = ERC721ReceiverComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        _heatingPeriod: u64,
        _totalStakedNftCount: felt252,
        _pointsPerSecond: u64,
        _userDeposits: LegacyMap<(ContractAddress, felt252), felt252>,
        _depositByDepositId: LegacyMap<felt252, DepositInfo>,
        _isDepositIdExist: LegacyMap<felt252, bool>,
        _userTotalStaked: LegacyMap<ContractAddress, felt252>,
        _users: LegacyMap<felt252, ContractAddress>,
        _userMinedPointSeason2: LegacyMap<ContractAddress, u64>,
        _userRegisteredAt: LegacyMap<ContractAddress, u64>,
        _userDepositCount: LegacyMap<ContractAddress, felt252>,
        _isUserRegistered: LegacyMap<ContractAddress, bool>,
        _uniqueUserCount: felt252,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        erc721Receiver: ERC721ReceiverComponent::Storage,
    }


    #[derive(Drop, starknet::Event)]
    struct Staked {
        operator: ContractAddress,
        tokenId: u256,
        time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
        operator: ContractAddress,
        tokenId: u256,
        time: u64
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        ReentrancyEvent: ReentrancyGuardComponent::Event,
        #[flat]
        Erc721ReceiverEvent: ERC721ReceiverComponent::Event,
    }

    extern fn u8_to_felt252(a: u8) -> felt252 nopanic;
    extern fn u128_to_felt252(a: u128) -> felt252 nopanic;
    extern fn contract_address_to_felt252(address: ContractAddress) -> felt252 nopanic;
    // point calculation = point / 10000 points per second
    #[constructor]
    fn constructor(
        ref self: ContractState, _owner: ContractAddress, _heatingPeriod: u64, pointsPerSecond: u64
    ) {
        self._pointsPerSecond.write(pointsPerSecond);
        self.src5.register_interface(0x150b7a02);
        self._heatingPeriod.write(_heatingPeriod);
        self.erc721Receiver.initializer();
        self.ownable.initializer(_owner);
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl StakeMaster of IChefGuardian<ContractState> {
        fn stake(ref self: ContractState, tokenId: u256) {
            self.reentrancy.start();
            let caller = get_caller_address();
            let this = get_contract_address();
            let now = get_block_timestamp();
            let sgn = sgn_contract();

            sgn.transferFrom(caller, this, tokenId);
            let _depositId = tokenId + now.into();
            let depositId = _depositId.try_into().unwrap() + contract_address_to_felt252(caller);
            let isDepositIdExist = self._isDepositIdExist.read(depositId);
            assert(isDepositIdExist == bool::False, 'deposit id already exist');
            self._isDepositIdExist.write(depositId, bool::True);

            if (self._isUserRegistered.read(caller) == bool::False) {
                self._isUserRegistered.write(caller, bool::True);
                self._users.write(self._uniqueUserCount.read(), caller);
                self._uniqueUserCount.write(self._uniqueUserCount.read() + 1);
                self._userRegisteredAt.write(caller, now);
            }

            let deposit = DepositInfo {
                isActive: bool::True, tokenId: tokenId, depositTime: now, owner: caller
            };

            self._userDeposits.write((caller, self._userDepositCount.read(caller)), depositId);
            self._userDepositCount.write(caller, self._userDepositCount.read(caller) + 1);
            self._depositByDepositId.write(depositId, deposit);
            self._userTotalStaked.write(caller, self._userTotalStaked.read(caller) + 1);
            self._totalStakedNftCount.write(self._totalStakedNftCount.read() + 1);

            self.reentrancy.end();
        }
        fn unstake(ref self: ContractState, depositId: felt252) {
            self.reentrancy.start();
            let caller = get_caller_address();
            let this = get_contract_address();
            let now = get_block_timestamp();
            let _depositInfo = self._depositByDepositId.read(depositId);
            assert(_depositInfo.owner == caller, 'owner must match with caller');
            assert(_depositInfo.isActive == bool::True, 'deposit is not active');

            let newDeposit = DepositInfo {
                owner: caller,
                tokenId: _depositInfo.tokenId,
                depositTime: _depositInfo.depositTime,
                isActive: bool::False
            };
            let mut minedPoint = 0;

            let mut depositStartTime: u64 = _depositInfo.depositTime;
            if (_depositInfo.depositTime <= 1719522680) {
                depositStartTime = 1719522680;
            }

            if (now > depositStartTime + self._heatingPeriod.read()) {
                let minedDuration = now - depositStartTime + self._heatingPeriod.read();
                minedPoint = minedDuration * self._pointsPerSecond.read() / 10000;
                let userCurrentMinedPoint = self._userMinedPointSeason2.read(caller);
                self._userMinedPointSeason2.write(caller, userCurrentMinedPoint + minedPoint);
            }

            sgn_contract().transferFrom(this, caller, _depositInfo.tokenId);
            self._depositByDepositId.write(depositId, newDeposit);
            self._userTotalStaked.write(caller, self._userTotalStaked.read(caller) - 1);
            self._totalStakedNftCount.write(self._totalStakedNftCount.read() - 1);

            self.reentrancy.end();
        }

        fn getUsers(
            self: @ContractState, startId: felt252, endId: felt252
        ) -> Array<UserLeaderboardStruct> {
            let mut i: felt252 = startId;
            let mut usersInfo = ArrayTrait::<UserLeaderboardStruct>::new();

            loop {
                let userAddress = self._users.read(i);
                let userInfo = self.getUserInfo(userAddress);
                if i == endId {
                    break;
                }
                let isUserValid = contract_address_to_felt252(userAddress);
                if (isUserValid == 0) {
                    break;
                }

                usersInfo.append(userInfo);

                i += 1;
            };

            usersInfo
        }

        fn getUserDeposits(
            self: @ContractState, user: ContractAddress
        ) -> Array<UserActiveDeposit> {
            let mut i: u8 = 0;
            let userDepositCount = self._userDepositCount.read(user);
            let mut _deposits = ArrayTrait::<UserActiveDeposit>::new();
            let now = get_block_timestamp();
            let heatingPeriod = self._heatingPeriod.read();
            loop {
                let _depositId = self._userDeposits.read((user, u8_to_felt252(i)));
                let depositInfo = self._depositByDepositId.read(_depositId);
                if userDepositCount == u8_to_felt252(i) {
                    break;
                }
                if (depositInfo.isActive == bool::True) {
                    let mut isHeating = bool::True;
                    let mut earnedPoint = 0;

                    let mut depositStartTime: u64 = depositInfo.depositTime;
                    if (depositInfo.depositTime <= 1719522680) {
                        depositStartTime = 1719522680;
                    }

                    if (now > depositStartTime + heatingPeriod) {
                        isHeating = bool::False;
                        let diff = now - depositStartTime + heatingPeriod;
                        earnedPoint = diff * self._pointsPerSecond.read();
                    }

                    let _userDepositInfo = UserActiveDeposit {
                        owner: depositInfo.owner,
                        tokenId: depositInfo.tokenId,
                        depositTime: depositInfo.depositTime,
                        isActive: depositInfo.isActive,
                        isHeating: isHeating,
                        earnedPoint: earnedPoint,
                        depositId: _depositId
                    };

                    _deposits.append(_userDepositInfo);
                }
                i += 1;
            };

            _deposits
        }

        fn getDeposit(self: @ContractState, depositId: felt252) -> UserActiveDeposit {
            let depositInfo = self._depositByDepositId.read(depositId);
            let now = get_block_timestamp();
            let heatingPeriod = self._heatingPeriod.read();

            let mut isHeating = bool::True;
            let mut earnedPoint = 0;
            if (now > depositInfo.depositTime + heatingPeriod) {
                isHeating = bool::False;
                let diff = now - depositInfo.depositTime + heatingPeriod;
                earnedPoint = diff * self._pointsPerSecond.read()
            }

            let _userDepositInfo = UserActiveDeposit {
                owner: depositInfo.owner,
                tokenId: depositInfo.tokenId,
                depositTime: depositInfo.depositTime,
                isActive: depositInfo.isActive,
                isHeating: isHeating,
                earnedPoint: earnedPoint,
                depositId: depositId
            };

            _userDepositInfo
        }

        fn getTotalUser(self: @ContractState) -> felt252 {
            self._uniqueUserCount.read()
        }
        fn getHeatingPeriod(self: @ContractState) -> u64 {
            self._heatingPeriod.read()
        }
        fn getPointsPerSecond(self: @ContractState) -> u64 {
            self._pointsPerSecond.read()
        }

        fn getUserMinedPoint(self: @ContractState, addr: ContractAddress) -> u64 {
            self._userMinedPointSeason2.read(addr)
        }

        fn setPointsPerSecond(ref self: ContractState, pointsPerSec: u64) {
            self.ownable.assert_only_owner();
            self._pointsPerSecond.write(pointsPerSec);
        }

        fn getUserInfo(self: @ContractState, userAddr: ContractAddress) -> UserLeaderboardStruct {
            let userTotalPoint = self._getUserTotalPoint(userAddr);
            let userRegistrationDate = self._userRegisteredAt.read(userAddr);
            let userTotalStaked = self._userTotalStaked.read(userAddr);
            let userLeaderboardData = UserLeaderboardStruct {
                userAddress: userAddr,
                stakeStartTime: userRegistrationDate,
                stakeAmount: userTotalStaked,
                userPoint: userTotalPoint
            };
            userLeaderboardData
        }
        fn getUserCurrentPoint(self: @ContractState, userAddr: ContractAddress) -> u64 {
            let userTotalPoint = self._getUserTotalPoint(userAddr);
            userTotalPoint
        }
        fn getTotalStaked(self: @ContractState) -> felt252 {
            let tStaked = self._totalStakedNftCount.read();
            tStaked
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _getUserTotalPoint(self: @ContractState, userAddr: ContractAddress) -> u64 {
            let userDeposits = self.getUserDeposits(userAddr);
            let mut i: u8 = 0;
            let mut totalEarnedPoint: u64 = 0;

            loop {
                if userDeposits.len() == i.into() {
                    break;
                }
                totalEarnedPoint += userDeposits.at(i.into()).clone().earnedPoint / 10000;
                i += 1;
            };
            let userMinedPoints = self._userMinedPointSeason2.read(userAddr);
            totalEarnedPoint + userMinedPoints
        }
    }
}
