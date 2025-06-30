#[test_only]
module defi_scaffold::dex_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin, TreasuryCap};
    #[test_only]
    use defi_scaffold::dex_core::{
        Self, TradingPair, PairRegistry, LiquidityToken, AdminCap, 
        EPairExists, EInvalidTokenOrder, ESlippageExceeded, EInvalidFee, EInsufficientLiquidity
    };

    // ================================
    // Test Constants
    // ================================
    
    const ADMIN_ADDRESS: address = @0x0;
    const USER_ADDRESS: address = @0x1;
    const INITIAL_BALANCE: u64 = 1_000_000_000; // 1B tokens
    const DEFAULT_FEE_BPS: u64 = 300; // 3%
    
    // ================================
    // Test Token Types
    // ================================
    
    public struct TokenA has drop {}
    public struct TokenB has drop {}
    public struct TokenC has drop {}

    // ================================
    // Test Setup Functions
    // ================================

    /// Sets up a basic test scenario with admin and user
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN_ADDRESS);
        
        // Initialize DEX system
        {
            dex_core::init_for_testing(scenario.ctx());
        };
        
        // Create test tokens
        {
            let ctx = scenario.ctx();
            let treasury_a = coin::create_treasury_cap_for_testing<TokenA>(ctx);
            let treasury_b = coin::create_treasury_cap_for_testing<TokenB>(ctx);
            let treasury_c = coin::create_treasury_cap_for_testing<TokenC>(ctx);
            
            transfer::public_transfer(treasury_a, ADMIN_ADDRESS);
            transfer::public_transfer(treasury_b, ADMIN_ADDRESS);
            transfer::public_transfer(treasury_c, ADMIN_ADDRESS);
        };
        
        // Transfer tokens to test users
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            let mut treasury_c = scenario.take_from_sender<TreasuryCap<TokenC>>();
            
            let user_a = treasury_a.mint(INITIAL_BALANCE, scenario.ctx());
            let user_b = treasury_b.mint(INITIAL_BALANCE, scenario.ctx());
            let user_c = treasury_c.mint(INITIAL_BALANCE, scenario.ctx());
            
            transfer::public_transfer(user_a, USER_ADDRESS);
            transfer::public_transfer(user_b, USER_ADDRESS);
            transfer::public_transfer(user_c, USER_ADDRESS);
            
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            scenario.return_to_sender(treasury_c);
        };
        
        scenario
    }


    /// Sets up a trading pair with initial liquidity
    fun setup_pair<TokenA, TokenB>(
        scenario: &mut Scenario,
        initial_a: u64,
        initial_b: u64,
    ) {
        // Create trading pair
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            
            let coin_a = coin::mint(&mut treasury_a, initial_a, scenario.ctx());
            let coin_b = coin::mint(&mut treasury_b, initial_b, scenario.ctx());
            
            let lp_tokens = dex_core::create_pair(
                &mut registry,
                coin_a,
                coin_b,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // Return LP tokens to admin
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            
            scenario.return_to_sender( treasury_a);
            scenario.return_to_sender( treasury_b);
            test_scenario::return_shared(registry);
        };
        
        // Verify pair creation
        scenario.next_tx(ADMIN_ADDRESS);
        {
            // Check that pair exists in registry
            let registry = scenario.take_shared<PairRegistry>();
            let pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            
            // Verify the pair exists in registry
            assert!(dex_core::pair_exists<TokenA, TokenB>(&registry), 0);
            
            // Return objects
            test_scenario::return_shared(registry);
            test_scenario::return_shared(pair);
        };
    }

    // ================================
    // Core Functionality Tests
    // ================================

    #[test]
    fun test_pair_creation() {
        let mut scenario = setup_test();
        
        // Test successful pair creation
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            
            let coin_a = treasury_a.mint(1000, scenario.ctx());
            let coin_b = treasury_b.mint( 2000, scenario.ctx());
            
            let lp_tokens = registry.create_pair(
                coin_a,
                coin_b,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // Verify initial liquidity tokens
            let lp_amount = lp_tokens.value();
            // Initial liquidity should be sqrt(1000 * 2000) = sqrt(2000000) ≈ 1414
            assert!(lp_amount > 1400 && lp_amount < 1500, 0);
            
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            test_scenario::return_shared(registry);
        };
        
        // Check reserves are set correctly
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            
            // Check reserves
            let (reserve_a, reserve_b) = pair.get_reserves();
            assert!(reserve_a == 1000, 0);
            assert!(reserve_b == 2000, 0);
            
            test_scenario::return_shared(pair);
        };
        
        // Verify registry is updated
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let registry = scenario.take_shared<PairRegistry>();
            
            // Check that pair exists in registry
            assert!(registry.pair_exists<TokenA, TokenB>(), 0);
            
            test_scenario::return_shared(registry);
        };
        
        scenario.end();
    }

    #[test]
    fun test_add_liquidity_proportional() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Add proportional liquidity
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            let mut treasury_b = scenario.take_from_address<TreasuryCap<TokenB>>(ADMIN_ADDRESS);
            
            // Get initial reserves
            let (initial_reserve_a, initial_reserve_b) = pair.get_reserves();

            // Mint tokens for adding liquidity (proportional)
            let add_a = 800; 
            let add_b = 1000; 

            let coin_a = treasury_a.mint(add_a, scenario.ctx());
            let coin_b = treasury_b.mint(add_b, scenario.ctx());

            let (remaining_a, remaining_b, lp_tokens) = pair.add_liquidity(
                coin_a,
                coin_b,
                1, // Min liquidity
                scenario.ctx()
            );

            // Verify LP tokens minted correctly
            let lp_amount = lp_tokens.value();
            // LP tokens should be proportional to the amount of B added (since it's the limiting factor)
            let expected_lp = (initial_reserve_a as u128) * (add_b as u128) / (initial_reserve_b as u128);

            assert!(lp_amount >= (expected_lp as u64) - 10, 2);
            
            // Clean up
            transfer::public_transfer(lp_tokens, USER_ADDRESS);
            transfer::public_transfer(remaining_a, USER_ADDRESS);
            transfer::public_transfer(remaining_b, USER_ADDRESS);
            
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_b);
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }

    #[test]
    fun test_add_liquidity_unbalanced() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Add unbalanced liquidity
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            let mut treasury_b = scenario.take_from_address<TreasuryCap<TokenB>>(ADMIN_ADDRESS);
            
            // Get initial reserves
            let (initial_reserve_a, initial_reserve_b) = pair.get_reserves();
            let initial_liquidity = pair.get_liquidity_supply();
            
            // Mint tokens for adding liquidity (unbalanced)
            let add_a = 800; // More than proportional
            let add_b = 1000; // Less than proportional (would need 1600 to maintain ratio)
            
            let coin_a = treasury_a.mint(add_a, scenario.ctx());
            let coin_b = treasury_b.mint(add_b, scenario.ctx());
            
            // Add liquidity
            let (remaining_a, remaining_b, lp_tokens) = pair.add_liquidity(
                coin_a,
                coin_b,
                1, // Min liquidity
                scenario.ctx()
            );
            
            // Verify optimal amounts calculated
            // Since B is the limiting factor, we should use all B and a portion of A
            let optimal_a = (add_b as u128) * (initial_reserve_a as u128) / (initial_reserve_b as u128);
            let expected_a_used = (optimal_a as u64);
            let expected_a_remaining = add_a - expected_a_used;
            
            // Check excess tokens returned
            assert!(coin::value(&remaining_a) == expected_a_remaining, 0);
            assert!(coin::value(&remaining_b) == 0, 1); // All B should be used
            
            // Verify LP tokens minted correctly
            let lp_amount = coin::value(&lp_tokens);
            // LP tokens should be proportional to the amount of B added (since it's the limiting factor)
            let expected_lp = (initial_liquidity as u128) * (add_b as u128) / (initial_reserve_b as u128);
            assert!(lp_amount >= (expected_lp as u64) - 10 && lp_amount <= (expected_lp as u64) + 10, 2);
            
            // Clean up
            transfer::public_transfer(lp_tokens, USER_ADDRESS);
            transfer::public_transfer(remaining_a, USER_ADDRESS);
            transfer::public_transfer(remaining_b, USER_ADDRESS);
            
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_b);
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }

    #[test]
    fun test_remove_liquidity() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // First get the LP tokens from admin
        scenario.next_tx(ADMIN_ADDRESS);
        {
            // Take LP tokens that were sent to admin during setup_pair
            let lp_tokens = scenario.take_from_sender<Coin<LiquidityToken<TokenA, TokenB>>>();
            // Transfer them to user for testing
            transfer::public_transfer(lp_tokens, USER_ADDRESS);
        };
        
        // Remove partial liquidity
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut lp_tokens = scenario.take_from_sender<Coin<LiquidityToken<TokenA, TokenB>>>();
            
            // Get initial state
            let (initial_reserve_a, initial_reserve_b) = pair.get_reserves();
            let initial_liquidity = pair.get_liquidity_supply();
            let lp_amount = lp_tokens.value();
            
            // Remove half of the liquidity
            let remove_amount = lp_amount / 2;
            let lp_to_remove = lp_tokens.split(remove_amount, scenario.ctx());
            
            // Calculate expected token amounts
            let expected_a = (remove_amount as u128) * (initial_reserve_a as u128) / (initial_liquidity as u128);
            let expected_b = (remove_amount as u128) * (initial_reserve_b as u128) / (initial_liquidity as u128);
            
            // Remove liquidity
            let (token_a, token_b) = pair.remove_liquidity(
                lp_to_remove,
                0, // Min amount A
                0, // Min amount B
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify proportional token withdrawal
            assert!(coin::value(&token_a) == (expected_a as u64), 0);
            assert!(coin::value(&token_b) == (expected_b as u64), 1);
            
            // Check LP tokens burned correctly
            let new_liquidity = pair.get_liquidity_supply();
            assert!(new_liquidity == initial_liquidity - remove_amount, 2);
            
            // Verify reserves updated
            let (new_reserve_a, new_reserve_b) = pair.get_reserves();
            assert!(new_reserve_a == initial_reserve_a - token_a.value(), 3);
            assert!(new_reserve_b == initial_reserve_b - token_b.value(), 4);
            
            // Clean up
            transfer::public_transfer(lp_tokens, USER_ADDRESS);
            transfer::public_transfer(token_a, USER_ADDRESS);
            transfer::public_transfer(token_b, USER_ADDRESS);
            
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }

    #[test]
    fun test_swap_a_to_b() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Execute swap A to B
        test_scenario::next_tx(&mut scenario, USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            
            // Get initial reserves
            let (reserve_a, reserve_b) = dex_core::get_reserves(&pair);
            
            // Amount to swap
            let swap_amount = 100;
            let coin_a = coin::mint(&mut treasury_a, swap_amount, test_scenario::ctx(&mut scenario));
            
            // Calculate expected output using constant product formula
            let expected_output = dex_core::get_amount_out(&pair, swap_amount, true);
            
            // Execute swap
            let output_coin = dex_core::swap_a_to_b(
                &mut pair,
                coin_a,
                expected_output - 5, // Allow for some slippage
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify constant product formula
            let output_amount = coin::value(&output_coin);
            assert!(output_amount == expected_output, 0);
            
            // Check reserves updated correctly
            let (new_reserve_a, new_reserve_b) = dex_core::get_reserves(&pair);
            assert!(new_reserve_a > reserve_a, 1); // Reserve A increased
            assert!(new_reserve_b < reserve_b, 2); // Reserve B decreased
            
            // Verify fees collected
            // Note: We can't directly check collected fees in this test as they're internal to the pair
            // But we can verify that the constant product formula holds with fees
            let k_before = (reserve_a as u128) * (reserve_b as u128);
            let k_after = (new_reserve_a as u128) * (new_reserve_b as u128);
            assert!(k_after >= k_before, 3); // k should increase or stay the same due to fees
            
            // Clean up
            transfer::public_transfer(output_coin, USER_ADDRESS);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_shared(pair);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_b_to_a() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Execute swap B to A
        test_scenario::next_tx(&mut scenario, USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_b = scenario.take_from_address<TreasuryCap<TokenB>>(ADMIN_ADDRESS);
            
            // Get initial reserves
            let (reserve_a, reserve_b) = dex_core::get_reserves(&pair);
            
            // Amount to swap
            let swap_amount = 200;
            let coin_b = coin::mint(&mut treasury_b, swap_amount, test_scenario::ctx(&mut scenario));
            
            // Calculate expected output using constant product formula
            let expected_output = dex_core::get_amount_out(&pair, swap_amount, false);
            
            // Execute swap
            let output_coin = dex_core::swap_b_to_a(
                &mut pair,
                coin_b,
                expected_output - 5, // Allow for some slippage
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify constant product formula
            let output_amount = coin::value(&output_coin);
            assert!(output_amount == expected_output, 0);
            
            // Check reserves updated correctly
            let (new_reserve_a, new_reserve_b) = dex_core::get_reserves(&pair);
            assert!(new_reserve_a < reserve_a, 1); // Reserve A decreased
            assert!(new_reserve_b > reserve_b, 2); // Reserve B increased
            
            // Verify fees collected
            let k_before = (reserve_a as u128) * (reserve_b as u128);
            let k_after = (new_reserve_a as u128) * (new_reserve_b as u128);
            assert!(k_after >= k_before, 3); // k should increase or stay the same due to fees
            
            // Clean up
            transfer::public_transfer(output_coin, USER_ADDRESS);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_b);
            test_scenario::return_shared(pair);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_fee_collection() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Execute several swaps to generate fees
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            let treasury_b = scenario.take_from_address<TreasuryCap<TokenB>>(ADMIN_ADDRESS);
            
            let mut i = 0;
            // Perform multiple swaps to accumulate fees
            while (i < 5) {
                // Swap A to B
                let coin_a = treasury_a.mint(50, scenario.ctx());
                let output_b = pair.swap_a_to_b(
                    coin_a,
                    0, // Min amount out
                    test_scenario::ctx(&mut scenario)
                );
                
                // Swap B to A
                let output_a = pair.swap_b_to_a(
                    output_b,
                    0, // Min amount out
                    test_scenario::ctx(&mut scenario)
                );

                i = i + 1;
                // Transfer output to user
                transfer::public_transfer(output_a, USER_ADDRESS);
            };
            
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_b);
            test_scenario::return_shared(pair);
        };
        
        // Collect fees as admin
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            
            // Collect fees
            let (fee_a, fee_b) = pair.collect_fees(
                &admin_cap,
                scenario.ctx()
            );
            
            // Verify fee amounts are correct
            // We can't precisely calculate the expected fees, but they should be non-zero
            assert!(coin::value(&fee_a) > 0, 0);
            assert!(coin::value(&fee_b) > 0, 1);
            
            // Clean up
            transfer::public_transfer(fee_a, ADMIN_ADDRESS);
            transfer::public_transfer(fee_b, ADMIN_ADDRESS);
            
            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pair);
        };
        
        // Check fees are reset after collection
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            
            // Collect fees again - should be zero
            let (fee_a, fee_b) = pair.collect_fees(
                &admin_cap,
                scenario.ctx()
            );
            
            // Verify fee amounts are zero
            assert!(coin::value(&fee_a) == 0, 2);
            assert!(coin::value(&fee_b) == 0, 3);
            
            // Clean up
            transfer::public_transfer(fee_a, ADMIN_ADDRESS);
            transfer::public_transfer(fee_b, ADMIN_ADDRESS);
            
            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }


    // ================================
    // Error Condition Tests
    // ================================

    #[test, expected_failure(abort_code = EPairExists)]
    fun test_duplicate_pair_creation() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Try creating same pair again
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            
            let coin_a = treasury_a.mint(500, scenario.ctx());
            let coin_b = treasury_b.mint(1000, scenario.ctx());
            
            // This should fail with EPairExists
            let lp_tokens = registry.create_pair(
                coin_a,
                coin_b,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // We should never reach this point
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            test_scenario::return_shared(registry);
        };
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EInvalidTokenOrder)]
    fun test_invalid_token_order() {
        let mut scenario = setup_test();
        
        // Try creating pair with identical tokens
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            
            // Create two coins of the same type
            let coin_a1 = treasury_a.mint(500, scenario.ctx());
            let coin_a2 = treasury_a.mint(1000, scenario.ctx());

            // This should fail with EInvalidTokenOrder because the types are the same
            let lp_tokens = registry.create_pair<TokenA, TokenA>(
                coin_a1,
                coin_a2,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // We should never reach this point
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            scenario.return_to_sender(treasury_a);
            test_scenario::return_shared(registry);
        };
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ESlippageExceeded)]
    fun test_slippage_protection() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 2000);
        
        // Execute swap with very high minimum output
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            
            // Amount to swap
            let swap_amount = 100;
            let coin_a = treasury_a.mint(swap_amount, scenario.ctx());
            
            // Calculate expected output
            let expected_output = pair.get_amount_out(swap_amount, true);
            
            // Execute swap with unrealistically high minimum output
            let output_coin = pair.swap_a_to_b(
                coin_a,
                expected_output * 2, // Require 2x the actual output - will fail
                scenario.ctx()
            );
            
            // We should never reach this point
            transfer::public_transfer(output_coin, USER_ADDRESS);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EInvalidFee)]
    fun test_invalid_fee_rate() {
        let mut scenario = setup_test();
        
        // Try creating pair with fee rate > MAX_FEE_BPS
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            
            let coin_a = treasury_a.mint(1000, scenario.ctx());
            let coin_b = treasury_b.mint(2000, scenario.ctx());
            
            // This should fail with EInvalidFee because MAX_FEE_BPS is 10000
            let invalid_fee_rate = 15000; // 150% fee is invalid
            
            let lp_tokens = registry.create_pair(
                coin_a,
                coin_b,
                invalid_fee_rate,
                test_scenario::ctx(&mut scenario)
            );
            
            // We should never reach this point
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            test_scenario::return_shared(registry);
        };
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EInsufficientLiquidity)]
    fun test_insufficient_liquidity_swap() {
        let mut scenario = setup_test();
        
        // Create pair but drain all liquidity
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            
            // Create pair with minimal liquidity
            let coin_a = treasury_a.mint(100, scenario.ctx());
            let coin_b = treasury_b.mint(100, scenario.ctx());
            
            let lp_tokens = registry.create_pair(
                coin_a,
                coin_b,
                DEFAULT_FEE_BPS,
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            test_scenario::return_shared(registry);
        };
        
        // Remove all liquidity
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let lp_tokens = scenario.take_from_sender<Coin<LiquidityToken<TokenA, TokenB>>>();
            
            let (token_a, token_b) = pair.remove_liquidity(
                lp_tokens,
                0, // Min amount A
                0, // Min amount B
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(token_a, ADMIN_ADDRESS);
            transfer::public_transfer(token_b, ADMIN_ADDRESS);
            test_scenario::return_shared(pair);
        };
        
        // Try swapping with insufficient liquidity
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            
            // Try to swap when there's no liquidity
            let coin_a = treasury_a.mint(10, scenario.ctx());
            
            // This should fail with EInsufficientLiquidity
            let output_coin = pair.swap_a_to_b(
                coin_a,
                0, // Min amount out
                scenario.ctx()
            );
            
            // We should never reach this point
            transfer::public_transfer(output_coin, USER_ADDRESS);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }

    // ================================
    // Integration Tests
    // ================================

    #[test]
    fun test_complete_trading_cycle() {
        let mut scenario = setup_test();
        
        // Create pair
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            
            let coin_a = treasury_a.mint(10000, scenario.ctx());
            let coin_b = treasury_b.mint(20000, scenario.ctx());
            
            let lp_tokens = registry.create_pair(
                coin_a,
                coin_b,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // Admin gets initial LP tokens
            transfer::public_transfer(lp_tokens, ADMIN_ADDRESS);
            
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            test_scenario::return_shared(registry);
        };
        
        // Add liquidity from first user
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut coin_a = scenario.take_from_sender<Coin<TokenA>>();
            let mut coin_b = scenario.take_from_sender<Coin<TokenB>>();
            
            // Split coins for adding liquidity
            let add_a = coin_a.split(5000, scenario.ctx());
            let add_b = coin_b.split(10000, scenario.ctx());
            
            let (remaining_a, remaining_b, lp_tokens) = pair.add_liquidity(
                add_a,
                add_b,
                1, // Min liquidity
                scenario.ctx()
            );
            
            // Return coins to user
            coin_a.join(remaining_a);
            coin_b.join(remaining_b);
            
            transfer::public_transfer(lp_tokens, USER_ADDRESS);
            scenario.return_to_sender(coin_a);
            scenario.return_to_sender(coin_b);
            test_scenario::return_shared(pair);
        };
        
        // Execute various swaps
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut coin_a = scenario.take_from_sender<Coin<TokenA>>();
            
            // Record initial reserves
            let (initial_reserve_a, initial_reserve_b) = pair.get_reserves();
            
            // Swap A to B
            let swap_amount_a = 1000;
            let swap_coin_a = coin_a.split(swap_amount_a, scenario.ctx());
            
            let output_b = pair.swap_a_to_b(
                swap_coin_a,
                0, // Min amount out
                scenario.ctx()
            );
            
            // Verify reserves changed correctly
            let (reserve_a_after_first_swap, reserve_b_after_first_swap) = pair.get_reserves();
            assert!(reserve_a_after_first_swap > initial_reserve_a, 0);
            assert!(reserve_b_after_first_swap < initial_reserve_b, 1);
            
            // Swap B to A
            let output_a = pair.swap_b_to_a(
                output_b,
                0, // Min amount out
                scenario.ctx()
            );
            
            // Verify reserves after second swap
            let (reserve_a_after_second_swap, reserve_b_after_second_swap) = pair.get_reserves();
            assert!(reserve_a_after_second_swap < reserve_a_after_first_swap, 2);
            assert!(reserve_b_after_second_swap > reserve_b_after_first_swap, 3);
            
            // Return output to user
            coin_a.join(output_a);
            
            scenario.return_to_sender(coin_a);
            test_scenario::return_shared(pair);
        };
        
        // Remove liquidity
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let lp_tokens = scenario.take_from_sender<Coin<LiquidityToken<TokenA, TokenB>>>();
            
            // Record state before removal
            let (reserve_a_before, reserve_b_before) = pair.get_reserves();
            let liquidity_before = pair.get_liquidity_supply();
            let lp_amount = lp_tokens.value();
            
            // Remove all user's liquidity
            let (token_a, token_b) = pair.remove_liquidity(
                lp_tokens,
                0, // Min amount A
                0, // Min amount B
                scenario.ctx()
            );
            
            // Verify liquidity removed correctly
            let (reserve_a_after, reserve_b_after) = pair.get_reserves();
            let liquidity_after = pair.get_liquidity_supply();
            
            assert!(reserve_a_after < reserve_a_before, 4);
            assert!(reserve_b_after < reserve_b_before, 5);
            assert!(liquidity_after == liquidity_before - lp_amount, 6);
            
            // Return tokens to user
            transfer::public_transfer(token_a, USER_ADDRESS);
            transfer::public_transfer(token_b, USER_ADDRESS);
            test_scenario::return_shared(pair);
        };
        
        // Collect fees as admin
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            
            // Collect fees
            let (fee_a, fee_b) = pair.collect_fees(
                &admin_cap,
                scenario.ctx()
            );
            
            // Verify fees collected (should be non-zero after swaps)
            assert!(coin::value(&fee_a) > 0, 7);
            assert!(coin::value(&fee_b) > 0, 8);
            
            // Return fees to admin
            transfer::public_transfer(fee_a, ADMIN_ADDRESS);
            transfer::public_transfer(fee_b, ADMIN_ADDRESS);
            
            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pair);
        };
        
        // Verify final state is consistent
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            
            // Get final reserves
            let (reserve_a, reserve_b) = pair.get_reserves();
            let k_final = (reserve_a as u128) * (reserve_b as u128);
            
            // Verify k value is still positive
            assert!(k_final > 0, 9);
            
            // Verify admin still has LP tokens (from initial liquidity)
            let admin_lp = scenario.take_from_sender<Coin<LiquidityToken<TokenA, TokenB>>>();
            assert!(coin::value(&admin_lp) > 0, 10);
            
            scenario.return_to_sender(admin_lp);
            test_scenario::return_shared(pair);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_pairs_interaction() {
        let mut scenario = setup_test();
        
        // Create multiple pairs (A-B, B-C, A-C)
        scenario.next_tx(ADMIN_ADDRESS);
        {
            let mut registry = scenario.take_shared<PairRegistry>();
            let mut treasury_a = scenario.take_from_sender<TreasuryCap<TokenA>>();
            let mut treasury_b = scenario.take_from_sender<TreasuryCap<TokenB>>();
            let mut treasury_c = scenario.take_from_sender<TreasuryCap<TokenC>>();
            
            // Create A-B pair
            let coin_a_for_ab = treasury_a.mint(10000, scenario.ctx());
            let coin_b_for_ab = treasury_b.mint(20000, scenario.ctx());
            
            let lp_tokens_ab = registry.create_pair(
                coin_a_for_ab,
                coin_b_for_ab,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // Create B-C pair
            let coin_b_for_bc = treasury_b.mint(15000, scenario.ctx());
            let coin_c_for_bc = treasury_c.mint(30000, scenario.ctx());
            
            let lp_tokens_bc = registry.create_pair(
                coin_b_for_bc,
                coin_c_for_bc,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // Create A-C pair
            let coin_a_for_ac = treasury_a.mint(8000, scenario.ctx());
            let coin_c_for_ac = treasury_c.mint(16000, scenario.ctx());
            
            let lp_tokens_ac = registry.create_pair(
                coin_a_for_ac,
                coin_c_for_ac,
                DEFAULT_FEE_BPS,
                scenario.ctx()
            );
            
            // Admin gets all LP tokens
            transfer::public_transfer(lp_tokens_ab, ADMIN_ADDRESS);
            transfer::public_transfer(lp_tokens_bc, ADMIN_ADDRESS);
            transfer::public_transfer(lp_tokens_ac, ADMIN_ADDRESS);
            
            scenario.return_to_sender(treasury_a);
            scenario.return_to_sender(treasury_b);
            scenario.return_to_sender(treasury_c);
            test_scenario::return_shared(registry);
        };
        
        // Execute swaps on all pairs
        scenario.next_tx(USER_ADDRESS);
        {
            // Take all pairs
            let mut pair_ab = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut pair_bc = scenario.take_shared<TradingPair<TokenB, TokenC>>();
            let mut pair_ac = scenario.take_shared<TradingPair<TokenA, TokenC>>();
            
            // Take user tokens
            let mut coin_a = scenario.take_from_sender<Coin<TokenA>>();
            
            // Record initial states
            let (ab_reserve_a_before, ab_reserve_b_before) = pair_ab.get_reserves();
            let (bc_reserve_b_before, bc_reserve_c_before) = pair_bc.get_reserves();
            let (ac_reserve_a_before, ac_reserve_c_before) = pair_ac.get_reserves();
            
            // Execute swap path: A -> B -> C
            let swap_amount_a = 5000;
            let swap_coin_a = coin_a.split(swap_amount_a, scenario.ctx());
            
            // Swap A to B
            let output_b = pair_ab.swap_a_to_b(
                swap_coin_a,
                0, // Min amount out
                scenario.ctx()
            );
            
            // Swap B to C
            let output_c = pair_bc.swap_a_to_b(
                output_b,
                0, // Min amount out
                scenario.ctx()
            );
            
            // Record intermediate states
            let (ab_reserve_a_mid, ab_reserve_b_mid) = pair_ab.get_reserves();
            let (bc_reserve_b_mid, bc_reserve_c_mid) = pair_bc.get_reserves();
            
            // Verify reserves changed correctly after first path
            assert!(ab_reserve_a_mid > ab_reserve_a_before, 0);
            assert!(ab_reserve_b_mid < ab_reserve_b_before, 1);
            assert!(bc_reserve_b_mid > bc_reserve_b_before, 2);
            assert!(bc_reserve_c_mid < bc_reserve_c_before, 3);
            
            // Now try direct path: A -> C
            let direct_swap_amount_a = 5000;
            let direct_swap_coin_a = coin_a.split(direct_swap_amount_a, scenario.ctx());
            
            // Swap A to C directly
            let direct_output_c = pair_ac.swap_a_to_b(
                direct_swap_coin_a,
                0, // Min amount out
                scenario.ctx()
            );         
            
            // Check cross-pair consistency
            // The k value (constant product) should increase in all pairs due to fees
            let ab_k_before = (ab_reserve_a_before as u128) * (ab_reserve_b_before as u128);
            let bc_k_before = (bc_reserve_b_before as u128) * (bc_reserve_c_before as u128);
            let ac_k_before = (ac_reserve_a_before as u128) * (ac_reserve_c_before as u128);
            
            let (ab_reserve_a_after, ab_reserve_b_after) = pair_ab.get_reserves();
            let (bc_reserve_b_after, bc_reserve_c_after) = pair_bc.get_reserves();
            let (ac_reserve_a_after, ac_reserve_c_after) = pair_ac.get_reserves();
            
            let ab_k_after = (ab_reserve_a_after as u128) * (ab_reserve_b_after as u128);
            let bc_k_after = (bc_reserve_b_after as u128) * (bc_reserve_c_after as u128);
            let ac_k_after = (ac_reserve_a_after as u128) * (ac_reserve_c_after as u128);
            
            // K should increase or stay the same due to fees
            assert!(ab_k_after >= ab_k_before, 4);
            assert!(bc_k_after >= bc_k_before, 5);
            assert!(ac_k_after >= ac_k_before, 6);
            
            // Return remaining tokens to user
            coin_a.join(coin::zero<TokenA>(scenario.ctx()));
            transfer::public_transfer(output_c, USER_ADDRESS);
            transfer::public_transfer(direct_output_c, USER_ADDRESS);
            
            // Return pairs to shared storage
            test_scenario::return_shared(pair_ab);
            test_scenario::return_shared(pair_bc);
            test_scenario::return_shared(pair_ac);
            scenario.return_to_sender(coin_a);
        };
        
        scenario.end();
    }

    // ================================
    // Math Verification Tests
    // ================================

    #[test]
    fun test_constant_product_invariant() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000, 1000);
        
        // Record initial k = x * y
        scenario.next_tx(USER_ADDRESS);
        {
            let mut pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            let mut treasury_a = scenario.take_from_address<TreasuryCap<TokenA>>(ADMIN_ADDRESS);
            
            // Get initial reserves
            let (reserve_a, reserve_b) = pair.get_reserves();
            let initial_k = (reserve_a as u128) * (reserve_b as u128);
            
            // Execute swap
            let swap_amount = 100;
            let coin_a = treasury_a.mint(swap_amount, scenario.ctx());
            
            let output_coin = pair.swap_a_to_b(
                coin_a,
                0, // Min amount out
                scenario.ctx()
            );
            
            // Get new reserves
            let (new_reserve_a, new_reserve_b) = pair.get_reserves();
            let new_k = (new_reserve_a as u128) * (new_reserve_b as u128);
            
            // Verify k' >= k (accounting for fees)
            assert!(new_k >= initial_k, 0);
            
            // Check precision handling
            // The difference between k' and k should be proportional to the fee
            let expected_fee_impact = ((swap_amount as u128) * (DEFAULT_FEE_BPS as u128)) / 10000;
            let k_increase = new_k - initial_k;
            
            // The actual k increase should be roughly proportional to the fee impact
            // We use a generous margin to account for rounding errors
            assert!(k_increase > 0, 1);
            assert!(k_increase <= (initial_k * expected_fee_impact / 100), 2);
            
            // Clean up
            transfer::public_transfer(output_coin, USER_ADDRESS);
            test_scenario::return_to_address(ADMIN_ADDRESS, treasury_a);
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }

    #[test]
    fun test_price_calculation_accuracy() {
        let mut scenario = setup_test();
        setup_pair<TokenA, TokenB>(&mut scenario, 1000000, 2000000);
        
        // Test price calculations with various amounts
        scenario.next_tx(USER_ADDRESS);
        {
            let pair = scenario.take_shared<TradingPair<TokenA, TokenB>>();
            
            // Get initial reserves
            let (reserve_a, reserve_b) = pair.get_reserves();
            
            // Test small swap amounts
            let small_amount = 10;
            let small_output = pair.get_amount_out(small_amount, true);
            
            // Test medium swap amounts
            let medium_amount = 10000;
            let medium_output = pair.get_amount_out(medium_amount, true);
            
            // Test large swap amounts
            let large_amount = 100000;
            let large_output = pair.get_amount_out(large_amount, true);
            
            // Verify precision in edge cases
            // For small amounts, output should be proportional to input
            let expected_small_output = (small_amount as u128) * (reserve_b as u128) / (reserve_a as u128);
            let small_diff = if (small_output > (expected_small_output as u64)) {
                small_output - (expected_small_output as u64)
            } else {
                (expected_small_output as u64) - small_output
            };
            // Allow for small rounding errors
            assert!(small_diff <= 1, 0);
            
            // For medium amounts, price impact should be noticeable but not extreme
            let naive_medium_output = (medium_amount as u128) * (reserve_b as u128) / (reserve_a as u128);
            assert!(medium_output < (naive_medium_output as u64), 1); // Price impact reduces output
            
            // For large amounts, price impact should be significant
            let naive_large_output = (large_amount as u128) * (reserve_b as u128) / (reserve_a as u128);
            assert!(large_output < (naive_large_output as u64), 2);
            
            // Check rounding behavior - should always round down for outputs
            let very_small_amount = 1;
            let very_small_output = pair.get_amount_out(very_small_amount, true);
            // If the theoretical output is less than 1, it should round to 0
            if ((very_small_amount as u128) * (reserve_b as u128) / (reserve_a as u128) < 1) {
                assert!(very_small_output == 0, 3);
            };
            
            test_scenario::return_shared(pair);
        };
        
        scenario.end();
    }
} 