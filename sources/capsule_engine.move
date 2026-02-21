/// Module: capsule_engine
/// The core engine of the Kairos protocol. Manages encrypted data references (blob_ids)
/// and enforces programmable unlock rules (Time-Locks, Dead-Man-Switch, Multi-Sig).
/// 
/// Refactored to support Frontend Draft/Sealed states and zkLogin-ready beneficiaries.
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
    const ESTATUS_NOT_DRAFT: u64 = 6;
    const ESTATUS_NOT_ACTIVE: u64 = 7;
    const EBENEFICIARY_ALREADY_LINKED: u64 = 8;

    // --- Status Constants ---
    const STATUS_DRAFT: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_UNLOCKED: u8 = 2;

    // --- Role Constants ---
    const ROLE_HEIR: u8 = 0;
    const ROLE_PROXY_GUARDIAN: u8 = 1;

    // --- Core Data Structures ---

    /// Represents a beneficiary of the capsule.
    /// Supports both raw addresses and zkLogin identifiers (hashed).
    struct Beneficiary has store, copy, drop {
        /// Optional Sui address. Can be added later if heir is identified by zk_id_hash first.
        addr: Option<address>,
        /// Hash of the zkLogin identifier (e.g., hash of Google/Apple JWT 'sub').
        zk_id_hash: vector<u8>,
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
        // --- Metadata for Frontend ---
        title: String,
        description: String,
        category: u8,              // 0=Personal, 1=Crypto, 2=Legal, 3=Business
        // --- Data Reference ---
        blob_id: String,           // Reference to Walrus blob
        seal_root_hash: vector<u8>, // Integrity verification
        // --- State ---
        status: u8,
        last_ping_ts_ms: u64,
        beneficiaries: vector<Beneficiary>,
        rules: UnlockRules,
    }

    // --- Events ---

    struct CapsuleCreated has copy, drop {
        capsule_id: ID,
        owner: address,
        title: String,
        category: u8,
    }

    struct CapsuleSealed has copy, drop {
        capsule_id: ID,
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

    /// Creates a new shared Capsule object in DRAFT status.
    /// Allows the owner to refine metadata and rules before sealing.
    public entry fun create_capsule(
        title: String,
        description: String,
        category: u8,
        blob_id: String,
        seal_root_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        let rules = UnlockRules {
            time_lock_ts_ms: option::none(),
            dead_man_threshold_ms: option::none(),
            approval_threshold: 0,
        };

        let id = object::new(ctx);
        let capsule_id = object::uid_to_inner(&id);

        let capsule = Capsule {
            id,
            owner: sender,
            title,
            description,
            category,
            blob_id,
            seal_root_hash,
            status: STATUS_DRAFT,
            last_ping_ts_ms: clock::timestamp_ms(clock),
            beneficiaries: vector::empty<Beneficiary>(),
            rules,
        };

        event::emit(CapsuleCreated {
            capsule_id,
            owner: sender,
            title,
            category,
        });

        transfer::share_object(capsule);
    }

    /// Transitions a capsule from DRAFT to ACTIVE.
    /// Once sealed, rules and beneficiaries are locked (except for address linking).
    public entry fun seal_capsule(
        capsule: &mut Capsule,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == capsule.owner, ENOT_OWNER);
        assert!(capsule.status == STATUS_DRAFT, ESTATUS_NOT_DRAFT);

        capsule.status = STATUS_ACTIVE;

        event::emit(CapsuleSealed {
            capsule_id: object::uid_to_inner(&capsule.id),
        });
    }

    // --- Update Functions (Only valid in STATUS_DRAFT) ---

    public entry fun update_metadata(
        capsule: &mut Capsule,
        title: String,
        description: String,
        category: u8,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == capsule.owner, ENOT_OWNER);
        assert!(capsule.status == STATUS_DRAFT, ESTATUS_NOT_DRAFT);
        capsule.title = title;
        capsule.description = description;
        capsule.category = category;
    }

    public entry fun update_rules(
        capsule: &mut Capsule,
        time_lock_ts_ms: Option<u64>,
        dead_man_threshold_ms: Option<u64>,
        approval_threshold: u8,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == capsule.owner, ENOT_OWNER);
        assert!(capsule.status == STATUS_DRAFT, ESTATUS_NOT_DRAFT);
        
        capsule.rules.time_lock_ts_ms = time_lock_ts_ms;
        capsule.rules.dead_man_threshold_ms = dead_man_threshold_ms;
        capsule.rules.approval_threshold = approval_threshold;
    }

    public entry fun add_beneficiary(
        capsule: &mut Capsule,
        addr: Option<address>,
        zk_id_hash: vector<u8>,
        role: u8,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == capsule.owner, ENOT_OWNER);
        assert!(capsule.status == STATUS_DRAFT, ESTATUS_NOT_DRAFT);
        
        vector::push_back(&mut capsule.beneficiaries, Beneficiary {
            addr,
            zk_id_hash,
            role,
            has_approved: false,
        });
    }

    /// Allows a beneficiary to link their Sui address if they were initially added via zk_id_hash.
    /// This can be done even after the capsule is ACTIVE.
    public entry fun link_beneficiary_address(
        capsule: &mut Capsule,
        zk_id_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let i = 0;
        let len = vector::length(&capsule.beneficiaries);
        let found = false;
        
        while (i < len) {
            let b = vector::borrow_mut(&mut capsule.beneficiaries, i);
            if (b.zk_id_hash == zk_id_hash) {
                assert!(option::is_none(&b.addr), EBENEFICIARY_ALREADY_LINKED);
                // In a real zkLogin scenario, we would verify a proof here.
                // For this refactor, we assume the frontend has verified the zkLogin
                // and the sender is the derived address.
                option::fill(&mut b.addr, sender);
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, ENOT_BENEFICIARY);
    }

    // --- Active Phase Functions ---

    /// Owner pings the capsule to prove they are still "alive/active".
    public entry fun ping(
        capsule: &mut Capsule,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == capsule.owner, ENOT_OWNER);
        assert!(capsule.status == STATUS_ACTIVE, ESTATUS_NOT_ACTIVE);

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
        assert!(capsule.status == STATUS_ACTIVE, ESTATUS_NOT_ACTIVE);

        let found = false;
        let i = 0;
        let len = vector::length(&capsule.beneficiaries);
        while (i < len) {
            let b = vector::borrow_mut(&mut capsule.beneficiaries, i);
            if (option::is_some(&b.addr) && *option::borrow(&b.addr) == sender) {
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
        assert!(capsule.status == STATUS_ACTIVE, ESTATUS_NOT_ACTIVE);

        let can_unlock = false;
        let now = clock::timestamp_ms(clock);

        // 1. Check Time-Lock Trigger
        if (option::is_some(&capsule.rules.time_lock_ts_ms)) {
            if (now >= *option::borrow(&capsule.rules.time_lock_ts_ms)) {
                can_unlock = true;
            };
        };

        // 2. Check Dead-Man-Switch Trigger
        if (!can_unlock && option::is_some(&capsule.rules.dead_man_threshold_ms)) {
            let threshold = *option::borrow(&capsule.rules.dead_man_threshold_ms);
            if (now > capsule.last_ping_ts_ms + threshold) {
                can_unlock = true;
            };
        };

        // 3. Check Multi-Sig Threshold Trigger
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
            let b = vector::borrow(&capsule.beneficiaries, i);
            if (option::is_some(&b.addr) && *option::borrow(&b.addr) == sender) {
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
}
