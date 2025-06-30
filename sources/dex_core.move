module defi_scaffold::dex_core;

use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::event;
use sui::table::{Self, Table};
use defi_scaffold::dex_helper;

// ================================
// Constants & Configuration
// ================================

/// Maximum fee percentage in basis points (100% = 10000 bps)
const MAX_FEE_BPS: u64 = 10000;

// ================================
// Error Codes
// ================================

const EInsufficientInput: u64 = 1;
const ESlippageExceeded: u64 = 2;
const EInvalidFee: u64 = 3;
const EPairExists: u64 = 4;
const EInsufficientLiquidity: u64 = 5;
const EInvalidTokenOrder: u64 = 6;
const EZeroAmount: u64 = 7;

// ================================
// Core Data Structures
// ================================

/// Represents a liquidity token for a specific trading pair
public struct LiquidityToken<phantom TokenA, phantom TokenB> has drop {}

/// Core trading pair structure
public struct TradingPair<phantom TokenA, phantom TokenB> has key {
    id: UID,
    reserve_a: Balance<TokenA>,
    reserve_b: Balance<TokenB>,
    liquidity_supply: Supply<LiquidityToken<TokenA, TokenB>>,
    fee_rate_bps: u64,
    protocol_fee_bps: u64,
    collected_fees_a: Balance<TokenA>,
    collected_fees_b: Balance<TokenB>,
}

/// Registry to track all created pairs
public struct PairRegistry has key {
    id: UID,
    pairs: Table<PairKey, ID>,
}

/// Key structure for pair lookup
public struct PairKey has copy, drop, store {
    token_a: TypeName,
    token_b: TypeName,
}

/// Admin capability for protocol management
public struct AdminCap has key, store {
    id: UID,
}

// ================================
// Events
// ================================

public struct PairCreated has copy, drop {
    pair_id: ID,
    token_a: TypeName,
    token_b: TypeName,
    creator: address,
}

public struct LiquidityAdded has copy, drop {
    pair_id: ID,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_minted: u64,
}

public struct LiquidityRemoved has copy, drop {
    pair_id: ID,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_burned: u64,
}

public struct SwapExecuted has copy, drop {
    pair_id: ID,
    trader: address,
    token_in: TypeName,
    token_out: TypeName,
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
}

// ================================
// Initialization
// ================================

fun init(ctx: &mut TxContext) {
    let registry = PairRegistry {
        id: object::new(ctx),
        pairs: table::new(ctx),
    };

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::share_object(registry);
    transfer::transfer(admin_cap, ctx.sender());
}

// ================================
// Core Pair Management
// ================================

/// Creates a new trading pair for two tokens
public fun create_pair<TokenA, TokenB>(
    registry: &mut PairRegistry,
    initial_a: Coin<TokenA>,
    initial_b: Coin<TokenB>,
    fee_rate_bps: u64,
    ctx: &mut TxContext,
): Coin<LiquidityToken<TokenA, TokenB>> {
    // Validate token order (A != B)
    assert!(validate_token_order<TokenA, TokenB>(), EInvalidTokenOrder);

    // Check pair doesn't already exist
    let token_a = type_name::get<TokenA>();
    let token_b = type_name::get<TokenB>();
    let pair_key = PairKey { token_a, token_b };
    assert!(!table::contains(&registry.pairs, pair_key), EPairExists);

    // Validate fee rate
    assert!(fee_rate_bps < MAX_FEE_BPS, EInvalidFee);

    // Check initial liquidity is not zero
    let amount_a = initial_a.value();
    let amount_b = initial_b.value();
    assert!(amount_a > 0 && amount_b > 0, EInsufficientInput);

    // Convert coins to balances
    let balance_a = initial_a.into_balance();
    let balance_b = initial_b.into_balance();

    // Calculate initial liquidity
    let initial_liquidity = dex_helper::calculate_initial_liquidity(amount_a, amount_b);

    // Create liquidity supply
    let mut lp_supply = balance::create_supply<LiquidityToken<TokenA, TokenB>>(LiquidityToken<TokenA, TokenB> {});

    // Mint initial liquidity tokens
    let lp_tokens = balance::increase_supply(&mut lp_supply, initial_liquidity);

    // Create new trading pair
    let pair_id = object::new(ctx);
    let pair = TradingPair<TokenA, TokenB> {
        id: pair_id,
        reserve_a: balance_a,
        reserve_b: balance_b,
        liquidity_supply: lp_supply,
        fee_rate_bps,
        protocol_fee_bps: 20, // Default 20% of fee goes to protocol
        collected_fees_a: balance::zero<TokenA>(),
        collected_fees_b: balance::zero<TokenB>(),
    };

    // Register pair in registry
    table::add(&mut registry.pairs, pair_key, object::id(&pair));

    // Emit pair created event
    event::emit(PairCreated {
        pair_id: object::id(&pair),
        token_a,
        token_b,
        creator: ctx.sender(),
    });

    // Share pair object and return liquidity tokens
    transfer::share_object(pair);
    coin::from_balance(lp_tokens, ctx)
}

// ================================
// Liquidity Management
// ================================

/// Adds liquidity to an existing pair
public fun add_liquidity<TokenA, TokenB>(
    pair: &mut TradingPair<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    min_liquidity: u64,
    ctx: &mut TxContext,
): (Coin<TokenA>, Coin<TokenB>, Coin<LiquidityToken<TokenA, TokenB>>) {
    let amount_a = token_a.value();
    let amount_b = token_b.value();

    // Check for non-zero inputs
    assert!(amount_a > 0 || amount_b > 0, EZeroAmount);

    let reserve_a = pair.reserve_a.value();
    let reserve_b = pair.reserve_b.value();
    let liquidity_supply = balance::supply_value(&pair.liquidity_supply);

    // Calculate deposit amounts and expected liquidity
    let (deposit_a, deposit_b) = if (reserve_a == 0 && reserve_b == 0) {
        // First deposit after initialization
        (amount_a, amount_b)
    } else {
        // Calculate optimal amounts based on the current ratio
        dex_helper::calculate_deposit_amounts(amount_a, amount_b, reserve_a, reserve_b)
    };

    // Handle deposits and calculate LP tokens
    let mut balance_a = token_a.into_balance();
    let mut balance_b = token_b.into_balance();

    // Split the balances according to the optimal amounts
    let deposit_balance_a = balance_a.split(deposit_a);
    let deposit_balance_b = balance_b.split(deposit_b);

    // Add to reserves
    pair.reserve_a.join(deposit_balance_a);
    pair.reserve_b.join(deposit_balance_b);

    // Calculate liquidity tokens to mint
    let lp_to_mint = if (liquidity_supply == 0) {
        dex_helper::calculate_initial_liquidity(deposit_a, deposit_b)
    } else {
        // Min(a_ratio, b_ratio) * liquidity_supply
        dex_helper::calculate_liquidity_amount(deposit_a, deposit_b, reserve_a, reserve_b, liquidity_supply)
    };

    // Ensure minimum liquidity is met
    assert!(lp_to_mint >= min_liquidity, ESlippageExceeded);

    // Mint LP tokens
    let lp_tokens = pair.liquidity_supply.increase_supply(lp_to_mint);

    // Emit event
    event::emit(LiquidityAdded {
        pair_id: object::id(pair),
        provider: ctx.sender(),
        amount_a: deposit_a,
        amount_b: deposit_b,
        liquidity_minted: lp_to_mint,
    });

    // Return remaining tokens and LP tokens
    (balance_a.into_coin(ctx), balance_b.into_coin(ctx), lp_tokens.into_coin(ctx))
}

/// Removes liquidity from a pair
public fun remove_liquidity<TokenA, TokenB>(
    pair: &mut TradingPair<TokenA, TokenB>,
    liquidity_tokens: Coin<LiquidityToken<TokenA, TokenB>>,
    min_amount_a: u64,
    min_amount_b: u64,
    ctx: &mut TxContext,
): (Coin<TokenA>, Coin<TokenB>) {
    let lp_amount = liquidity_tokens.value();
    assert!(lp_amount > 0, EZeroAmount);

    // Get current reserves and liquidity supply
    let reserve_a = pair.reserve_a.value();
    let reserve_b = pair.reserve_b.value();
    let liquidity_supply = balance::supply_value(&pair.liquidity_supply);

    // Calculate withdrawal amounts proportionally
    let (amount_a, amount_b) = dex_helper::calculate_withdrawal_amounts(lp_amount, reserve_a, reserve_b, liquidity_supply);

    // Validate minimum amounts
    assert!((amount_a as u64) >= min_amount_a, ESlippageExceeded);
    assert!((amount_b as u64) >= min_amount_b, ESlippageExceeded);

    // Convert liquidity tokens to balance and burn
    let lp_balance = liquidity_tokens.into_balance();
    pair.liquidity_supply.decrease_supply(lp_balance);

    // Withdraw from reserves
    let token_a = pair.reserve_a.split(amount_a).into_coin(ctx);
    let token_b = pair.reserve_b.split(amount_b).into_coin(ctx);

    // Emit liquidity removed event
    event::emit(LiquidityRemoved {
        pair_id: object::id(pair),
        provider: ctx.sender(),
        amount_a: (amount_a as u64),
        amount_b: (amount_b as u64),
        liquidity_burned: lp_amount,
    });

    (token_a, token_b)
}

// ================================
// Trading Functions
// ================================

/// Swaps token A for token B
public fun swap_a_to_b<TokenA, TokenB>(
    pair: &mut TradingPair<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_amount_out: u64,
    ctx: &mut TxContext,
): Coin<TokenB> {
    let input_amount = token_a.value();
    assert!(input_amount > 0, EZeroAmount);

    // Get current reserves
    let reserve_a = pair.reserve_a.value();
    let reserve_b = pair.reserve_b.value();

    // Check liquidity
    assert!(reserve_a > 0 && reserve_b > 0, EInsufficientLiquidity);

    // Calculate fee
    let (input_after_fee, fee_amount) = dex_helper::calculate_input_fees(input_amount, pair.fee_rate_bps);

    // Calculate output using constant product formula
    let output_amount = dex_helper::calculate_swap_output(
        input_after_fee,
        reserve_a,
        reserve_b,
        pair.fee_rate_bps,
    );

    // Check slippage
    assert!(output_amount >= min_amount_out, ESlippageExceeded);

    // Calculate protocol fee
    let (protocol_fee, lp_fee) = dex_helper::calculate_protocol_fees(fee_amount, pair.protocol_fee_bps);

    // Update reserves
    // Add input tokens to reserve A
    pair.reserve_a.join(token_a.into_balance());

    // Collect protocol fee
    if (protocol_fee > 0) {
        pair.collected_fees_a.join(
            pair.reserve_a.split(protocol_fee),
        );
    };

    // Collect LP fee
    pair.collected_fees_a.join(
        pair.reserve_a.split(lp_fee),
    );

    // Withdraw output tokens from reserve B
    let output_coin = pair.reserve_b.split(output_amount).into_coin(ctx);

    // Emit swap event
    event::emit(SwapExecuted {
        pair_id: object::id(pair),
        trader: ctx.sender(),
        token_in: type_name::get<TokenA>(),
        token_out: type_name::get<TokenB>(),
        amount_in: input_amount,
        amount_out: output_amount,
        fee_amount,
    });

    output_coin
}

/// Swaps token B for token A
public fun swap_b_to_a<TokenA, TokenB>(
    pair: &mut TradingPair<TokenA, TokenB>,
    token_b: Coin<TokenB>,
    min_amount_out: u64,
    ctx: &mut TxContext,
): Coin<TokenA> {
    let input_amount = token_b.value();
    assert!(input_amount > 0, EZeroAmount);

    // Get current reserves
    let reserve_a = pair.reserve_a.value();
    let reserve_b = pair.reserve_b.value();

    // Check liquidity
    assert!(reserve_a > 0 && reserve_b > 0, EInsufficientLiquidity);

    // Calculate fee
    let (input_after_fee, fee_amount) = dex_helper::calculate_input_fees(input_amount, pair.fee_rate_bps);

    // Calculate output using constant product formula
    let output_amount = dex_helper::calculate_swap_output(
        input_after_fee,
        reserve_b,
        reserve_a,
        pair.fee_rate_bps,
    );

    // Check slippage
    assert!(output_amount >= min_amount_out, ESlippageExceeded);

    // Calculate protocol fee
    let (protocol_fee, lp_fee) = dex_helper::calculate_protocol_fees(fee_amount, pair.protocol_fee_bps);

    // Update reserves
    // Add input tokens to reserve B
    pair.reserve_b.join(token_b.into_balance());

    // Collect protocol fee
    if (protocol_fee > 0) {
        pair.collected_fees_b.join(pair.reserve_b.split(protocol_fee));
    };

    // Collect LP fee
    pair.collected_fees_b.join(pair.reserve_b.split(lp_fee));

    // Withdraw output tokens from reserve A
    let output_coin = pair.reserve_a.split(output_amount).into_coin(ctx);

    // Emit swap event
    event::emit(SwapExecuted {
        pair_id: object::id(pair),
        trader: ctx.sender(),
        token_in: type_name::get<TokenB>(),
        token_out: type_name::get<TokenA>(),
        amount_in: input_amount,
        amount_out: output_amount,
        fee_amount,
    });

    output_coin
}

// ================================
// Admin Functions
// ================================

/// Updates fee rates (admin only)
public fun update_fees<TokenA, TokenB>(
    pair: &mut TradingPair<TokenA, TokenB>,
    _: &AdminCap,
    new_fee_rate_bps: u64,
    new_protocol_fee_bps: u64,
) {
    // Validate fee rates
    assert!(new_fee_rate_bps < MAX_FEE_BPS, EInvalidFee);
    assert!(new_protocol_fee_bps <= 100, EInvalidFee);

    // Update pair fee configuration
    pair.fee_rate_bps = new_fee_rate_bps;
    pair.protocol_fee_bps = new_protocol_fee_bps;
}

/// Collects protocol fees (admin only)
public fun collect_fees<TokenA, TokenB>(
    pair: &mut TradingPair<TokenA, TokenB>,
    _: &AdminCap,
    ctx: &mut TxContext,
): (Coin<TokenA>, Coin<TokenB>) {
    // Extract collected fees
    let fee_a_amount = pair.collected_fees_a.value();
    let fee_b_amount = pair.collected_fees_b.value();

    // Create coins from collected fees
    let coin_a = if (fee_a_amount > 0) {
        coin::from_balance(pair.collected_fees_a.withdraw_all(), ctx)
    } else {
        coin::zero<TokenA>(ctx)
    };

    let coin_b = if (fee_b_amount > 0) {
        coin::from_balance(pair.collected_fees_b.withdraw_all(), ctx)
    } else {
        coin::zero<TokenB>(ctx)
    };

    (coin_a, coin_b)
}

// ================================
// Helper Functions
// ================================

/// Validates that token types are in correct alphabetical order
fun validate_token_order<TokenA, TokenB>(): bool {
    let typeA = type_name::get<TokenA>();
    let typeB = type_name::get<TokenB>();

    typeA != typeB
}

// ================================
// Test Functions
// ================================

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

// ================================
// View Functions
// ================================

/// Gets the current reserves of a trading pair
#[test_only]
public fun get_reserves<TokenA, TokenB>(
    pair: &TradingPair<TokenA, TokenB>
): (u64, u64) {
    (pair.reserve_a.value(), pair.reserve_b.value())
}

/// Gets the current liquidity supply
#[test_only]
public fun get_liquidity_supply<TokenA, TokenB>(
    pair: &TradingPair<TokenA, TokenB>
): u64 {
    balance::supply_value(&pair.liquidity_supply)
}

/// Gets current fee rates
#[test_only]
public fun get_fee_rates<TokenA, TokenB>(
    pair: &TradingPair<TokenA, TokenB>
): (u64, u64) {
    (pair.fee_rate_bps, pair.protocol_fee_bps)
}

/// Checks if a pair exists in the registry
#[test_only]
public fun pair_exists<TokenA, TokenB>(
    registry: &PairRegistry
): bool {
    let token_a = type_name::get<TokenA>();
    let token_b = type_name::get<TokenB>();
    let pair_key = PairKey { token_a, token_b };
    table::contains(&registry.pairs, pair_key)
}

/// Calculates expected output for a given input
#[test_only]
public fun get_amount_out<TokenA, TokenB>(
    pair: &TradingPair<TokenA, TokenB>,
    amount_in: u64,
    is_a_to_b: bool,
): u64 {
    let (reserve_a, reserve_b) = get_reserves(pair);
    let (input_after_fee, _) = dex_helper::calculate_input_fees(amount_in, pair.fee_rate_bps);
    
    if (is_a_to_b) {
        dex_helper::calculate_swap_output(input_after_fee, reserve_a, reserve_b, pair.fee_rate_bps)
    } else {
        dex_helper::calculate_swap_output(input_after_fee, reserve_b, reserve_a, pair.fee_rate_bps)
    }
}
