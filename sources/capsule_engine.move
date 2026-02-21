/// Module 1: capsule_engine
/// The core engine of the Kairos protocol. Manages encrypted data references (blob_ids)
/// and enforces programmable unlock rules (Time-Locks, Dead-Man-Switch, Multi-Sig).
module kairos::capsule_engine {
    use std::string::String;
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::event;

    // --- Errors ---
    const ENOT_OWNER: u64 = 0;
    const ENOT_BENEFICIARY: u64 = 1;
    const EALREADY_UNLOCKED: u64 = 2;
    const ENOT_READY_FOR_UNLOCK: u64 = 3;
    const ENOT_UNLOCKED: u64 = 4;
    const EINVALID_THRESHOLD: u64 = 5;

    // --- Status Constants ---
    const STATUS_ACTIVE: u8 = 0;
    const STATUS_UNLOCKED: u8 = 1;

    // --- Role Constants ---
    const ROLE_HEIR: u8 = 0;
    const ROLE_PROXY_GUARDIAN: u8 = 1;

    // --- Core Data Structures ---

    /// Represents a beneficiary of the capsule.
    struct Beneficiary has store, copy, drop {
        addr: address,
        role: u8,
        has_approved: bool,
    }

    /// Rules that must be met to unlock the capsule.
    struct UnlockRules has store, copy, drop {
        /// Timestamp (ms) after which the capsule can be unlocked.
        time_lock_ts_ms: Option<u64>,
        /// Duration (ms) since the last ping after which the capsule is considered "dead".
        dead_man_threshold_ms: Option<u64>,
        /// Number of heirs/guardians required to approve for manual unlock.
        approval_threshold: u8,
    }

    /// The Shared Object representing a time-locked data escrow.
    struct Capsule has key {
        id: UID,
        owner: address,
        blob_id: String,           // Reference to Walrus blob
        seal_root_hash: vector<u8>, // Integrity verification
        status: u8,
        last_ping_ts_ms: u64,
        beneficiaries: vector<Beneficiary>,
        rules: UnlockRules,
    }

    // --- Events ---

    struct CapsuleCreated has copy, drop {
        capsule_id: ID,
        owner: address,
        blob_id: String,
    }

    struct PingRecorded has copy, drop {
        capsule_id: ID,
        timestamp: u64,
    }

    struct UnlockApproved has copy, drop {
        capsule_id: ID,
        beneficiary: address,
    }

    struct CapsuleUnlocked has copy, drop {
        capsule_id: ID,
    }

    struct CapsuleClaimed has copy, drop {
        capsule_id: ID,
        beneficiary: address,
        blob_id: String,
    }

    // --- Entry Functions ---

    /// Creates a new shared Capsule object with specific rules and beneficiaries.
    public entry fun create_capsule(
        blob_id: String,
        seal_root_hash: vector<u8>,
        beneficiary_addrs: vector<address>,
        beneficiary_roles: vector<u8>,
        time_lock_ts_ms: Option<u64>,
        dead_man_threshold_ms: Option<u64>,
        approval_threshold: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let beneficiaries = vector::empty<Beneficiary>();
        let len = vector::length(&beneficiary_addrs);
        
        // Ensure threshold is valid
        assert!(approval_threshold <= (len as u8), EINVALID_THRESHOLD);

        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&beneficiary_addrs, i);
            let role = *vector::borrow(&beneficiary_roles, i);
            vector::push_back(&mut beneficiaries, Beneficiary {
                addr,
                role,
                has_approved: false,
            });
            i = i + 1;
        };

        let rules = UnlockRules {
            time_lock_ts_ms,
            dead_man_threshold_ms,
            approval_threshold,
        };

        let id = object::new(ctx);
        let capsule_id = object::uid_to_inner(&id);

        let capsule = Capsule {
            id,
            owner: sender,
            blob_id,
            seal_root_hash,
            status: STATUS_ACTIVE,
            last_ping_ts_ms: clock::timestamp_ms(clock),
            beneficiaries,
            rules,
        };

        event::emit(CapsuleCreated {
            capsule_id,
            owner: sender,
            blob_id,
        });

        transfer::share_object(capsule);
    }

    /// Owner pings the capsule to prove they are still "alive/active".
    public entry fun ping(
        capsule: &mut Capsule,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == capsule.owner, ENOT_OWNER);
        assert!(capsule.status == STATUS_ACTIVE, EALREADY_UNLOCKED);

        let now = clock::timestamp_ms(clock);
        capsule.last_ping_ts_ms = now;

        event::emit(PingRecorded {
            capsule_id: object::uid_to_inner(&capsule.id),
            timestamp: now,
        });
    }

    /// A beneficiary approves the unlock of the capsule.
    public entry fun approve_unlock(
        capsule: &mut Capsule,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(capsule.status == STATUS_ACTIVE, EALREADY_UNLOCKED);

        let found = false;
        let i = 0;
        let len = vector::length(&capsule.beneficiaries);
        while (i < len) {
            let b = vector::borrow_mut(&mut capsule.beneficiaries, i);
            if (b.addr == sender) {
                b.has_approved = true;
                found = true;
                break
            };
            i = i + 1;
        };

        assert!(found, ENOT_BENEFICIARY);

        event::emit(UnlockApproved {
            capsule_id: object::uid_to_inner(&capsule.id),
            beneficiary: sender,
        });
    }

    /// Evaluates all rules to see if the capsule can be moved to UNLOCKED status.
    public entry fun evaluate_and_unlock(
        capsule: &mut Capsule,
        clock: &Clock
    ) {
        assert!(capsule.status == STATUS_ACTIVE, EALREADY_UNLOCKED);

        let can_unlock = false;
        let now = clock::timestamp_ms(clock);

        // 1. Check Time-Lock
        if (option::is_some(&capsule.rules.time_lock_ts_ms)) {
            let lock_time = *option::borrow(&capsule.rules.time_lock_ts_ms);
            if (now >= lock_time) {
                can_unlock = true;
            };
        };

        // 2. Check Dead-Man-Switch
        if (!can_unlock && option::is_some(&capsule.rules.dead_man_threshold_ms)) {
            let threshold = *option::borrow(&capsule.rules.dead_man_threshold_ms);
            if (now > capsule.last_ping_ts_ms + threshold) {
                can_unlock = true;
            };
        };

        // 3. Check Multi-Sig Threshold
        if (!can_unlock && capsule.rules.approval_threshold > 0) {
            let approvals = 0;
            let i = 0;
            let len = vector::length(&capsule.beneficiaries);
            while (i < len) {
                if (vector::borrow(&capsule.beneficiaries, i).has_approved) {
                    approvals = approvals + 1;
                };
                i = i + 1;
            };
            if (approvals >= capsule.rules.approval_threshold) {
                can_unlock = true;
            };
        };

        assert!(can_unlock, ENOT_READY_FOR_UNLOCK);

        capsule.status = STATUS_UNLOCKED;

        event::emit(CapsuleUnlocked {
            capsule_id: object::uid_to_inner(&capsule.id),
        });
    }

    /// Allows an authorized beneficiary to "claim" the capsule once it is UNLOCKED.
    /// Emits the blob_id for retrieval and decryption.
    public entry fun claim(
        capsule: &Capsule,
        ctx: &mut TxContext
    ) {
        assert!(capsule.status == STATUS_UNLOCKED, ENOT_UNLOCKED);

        let sender = tx_context::sender(ctx);
        let authorized = false;
        let i = 0;
        let len = vector::length(&capsule.beneficiaries);
        while (i < len) {
            if (vector::borrow(&capsule.beneficiaries, i).addr == sender) {
                authorized = true;
                break
            };
            i = i + 1;
        };

        assert!(authorized, ENOT_BENEFICIARY);

        event::emit(CapsuleClaimed {
            capsule_id: object::uid_to_inner(&capsule.id),
            beneficiary: sender,
            blob_id: capsule.blob_id,
        });
    }

    // --- Test Placeholders ---

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_dead_man_switch_success() {
        let owner = @0xACE;
        let heir = @0xB0B;
        let scenario_val = test_scenario::begin(owner);
        let scenario = &mut scenario_val;
        
        // Implementation for testing would go here:
        // 1. Create clock
        // 2. Create capsule with dead_man_threshold_ms = 1000
        // 3. Advance clock by 1001 ms
        // 4. evaluate_and_unlock
        // 5. Assert status is UNLOCKED
        
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_multi_heir_threshold() {
        // Implementation for testing would go here:
        // 1. Create capsule with threshold = 2 and 3 heirs
        // 2. Heir 1 approves
        // 3. evaluate_and_unlock fails
        // 4. Heir 2 approves
        // 5. evaluate_and_unlock succeeds
    }
}
