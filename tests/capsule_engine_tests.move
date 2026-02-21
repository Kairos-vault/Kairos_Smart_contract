#[test_only]
module kairos::capsule_engine_tests {
    use std::string::{Self};
    use std::option;
    use sui::test_scenario;
    use sui::clock::{Self};
    use kairos::capsule_engine::{Self, Capsule};

    #[test]
    fun test_capsule_lifecycle() {
        let owner = @0xACE;
        let beneficiary_1 = @0xB0B;
        let scenario_val = test_scenario::begin(owner);
        let scenario = &mut scenario_val;
        
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        // 1. Create Capsule (DRAFT)
        capsule_engine::create_capsule(
            string::utf8(b"My Crypto Assets"),
            string::utf8(b"Recovery for my crypto wallet"),
            1, // Category: Crypto
            string::utf8(b"walrus_blob_id_123"),
            vector::empty(),
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::next_tx(scenario, owner);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            
            // 2. Add Beneficiary and Rules while in DRAFT
            capsule_engine::add_beneficiary(
                &mut capsule,
                option::some(beneficiary_1),
                vector::empty(), // No zk_id_hash for now
                0, // Role: Heir
                test_scenario::ctx(scenario)
            );

            capsule_engine::update_rules(
                &mut capsule,
                option::some(1000), // Time-lock: 1000ms
                option::none(),
                0,
                test_scenario::ctx(scenario)
            );

            // 3. Seal Capsule
            capsule_engine::seal_capsule(&mut capsule, test_scenario::ctx(scenario));
            
            test_scenario::return_shared(capsule);
        };

        // 4. Advance clock and unlock
        clock::set_for_testing(&mut clock, 1001);
        
        test_scenario::next_tx(scenario, owner);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            capsule_engine::evaluate_and_unlock(&mut capsule, &clock);
            test_scenario::return_shared(capsule);
        };

        // 5. Claim as beneficiary
        test_scenario::next_tx(scenario, beneficiary_1);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            capsule_engine::claim(&capsule, test_scenario::ctx(scenario));
            test_scenario::return_shared(capsule);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_zklogin_flow() {
        let owner = @0xACE;
        let beneficiary_addr = @0xB0B;
        let zk_id_hash = b"hashed_email_identifier";
        
        let scenario_val = test_scenario::begin(owner);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        // 1. Create Capsule
        capsule_engine::create_capsule(
            string::utf8(b"Family Legal Docs"),
            string::utf8(b"Encrypted legal documents"),
            2, // Category: Legal
            string::utf8(b"blob_456"),
            vector::empty(),
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::next_tx(scenario, owner);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            
            // 2. Add beneficiary by zk_id_hash ONLY (no address yet)
            capsule_engine::add_beneficiary(
                &mut capsule,
                option::none(),
                zk_id_hash,
                0,
                test_scenario::ctx(scenario)
            );

            // 3. Seal Capsule
            capsule_engine::seal_capsule(&mut capsule, test_scenario::ctx(scenario));
            test_scenario::return_shared(capsule);
        };

        // 4. Link address later (even when ACTIVE)
        test_scenario::next_tx(scenario, beneficiary_addr);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            capsule_engine::link_beneficiary_address(
                &mut capsule,
                zk_id_hash,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(capsule);
        };

        // 5. Verify it's linked by trying to approve
        test_scenario::next_tx(scenario, beneficiary_addr);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            capsule_engine::approve_unlock(&mut capsule, test_scenario::ctx(scenario));
            test_scenario::return_shared(capsule);
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = kairos::capsule_engine::ESTATUS_NOT_DRAFT)]
    fun test_fail_update_after_seal() {
        let owner = @0xACE;
        let scenario_val = test_scenario::begin(owner);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        capsule_engine::create_capsule(
            string::utf8(b"Title"),
            string::utf8(b"Desc"),
            0,
            string::utf8(b"blob"),
            vector::empty(),
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::next_tx(scenario, owner);
        {
            let capsule = test_scenario::take_shared<Capsule>(scenario);
            capsule_engine::seal_capsule(&mut capsule, test_scenario::ctx(scenario));
            
            // This should fail
            capsule_engine::update_metadata(
                &mut capsule,
                string::utf8(b"New Title"),
                string::utf8(b"New Desc"),
                1,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(capsule);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }
}
