/// Module 2: reputation_sbt
/// This module manages Soulbound Tokens (SBTs) that track user reputation
/// within the Kairos protocol based on their reliability and ping streaks.
module kairos::reputation_sbt {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;

    // --- Errors ---
    const ENOT_AUTHORIZED: u64 = 0;

    // --- Core Data Structures ---

    /// Soulbound Token: Non-transferable reputation badge.
    struct LegacySBT has key {
        id: UID,
        owner: address,
        trust_score: u64,
    }

    /// Admin Capability to manage reputation scores.
    struct AdminCap has key, store {
        id: UID,
    }

    // --- Events ---

    struct SBTMinted has copy, drop {
        sbt_id: object::ID,
        owner: address,
        initial_score: u64,
    }

    struct TrustScoreUpdated has copy, drop {
        sbt_id: object::ID,
        new_score: u64,
    }

    // --- Initializer ---

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    // --- Public Functions ---

    /// Mints a new LegacySBT for a user. Typically called by the protocol or owner.
    public entry fun mint_sbt(
        _admin: &AdminCap,
        recipient: address,
        initial_score: u64,
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);
        let sbt_id = object::uid_to_inner(&id);
        
        let sbt = LegacySBT {
            id,
            owner: recipient,
            trust_score: initial_score,
        };

        event::emit(SBTMinted {
            sbt_id,
            owner: recipient,
            initial_score,
        });

        // Soulbound: transfer directly to recipient, but logic prevents standard transfer functions
        // since it doesn't have the `store` ability.
        transfer::transfer(sbt, recipient);
    }

    /// Updates the trust score of an existing SBT.
    public entry fun update_trust_score(
        _admin: &AdminCap,
        sbt: &mut LegacySBT,
        new_score: u64,
    ) {
        sbt.trust_score = new_score;

        event::emit(TrustScoreUpdated {
            sbt_id: object::uid_to_inner(&sbt.id),
            new_score,
        });
    }

    // --- Getters ---

    public fun trust_score(sbt: &LegacySBT): u64 {
        sbt.trust_score
    }
}
