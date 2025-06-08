module defi_scaffold::dex_utils {
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use defi_scaffold::dex_core::{
        Self, 
        TradingPair, 
        PairRegistry, 
        LiquidityToken, 
        AdminCap
    };

    // ================================
    // Error Codes
    // ================================
    
    #[error]
    const EZeroBalance: u64 = 1;

    // ================================
    // Convenience Functions for SDK
    // ================================

    /// Creates a pair and transfers LP tokens to sender
    public fun create_pair_and_transfer<TokenA, TokenB>(
        registry: &mut PairRegistry,
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        fee_rate_bps: u64,
        ctx: &mut TxContext,
    ) {
        // TODO: Call dex_core::create_pair
        // TODO: Transfer LP tokens to sender
        // TODO: Handle any leftover tokens
    }

    /// Adds liquidity and transfers results to sender
    public fun add_liquidity_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        min_liquidity: u64,
        ctx: &mut TxContext,
    ) {
        // TODO: Call dex_core::add_liquidity
        // TODO: Transfer all results to sender
    }

    /// Removes liquidity and transfers tokens to sender
    public fun remove_liquidity_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        liquidity_tokens: Coin<LiquidityToken<TokenA, TokenB>>,
        min_amount_a: u64,
        min_amount_b: u64,
        ctx: &mut TxContext,
    ) {
        // TODO: Call dex_core::remove_liquidity
        // TODO: Transfer tokens to sender
    }

    /// Swaps A to B and transfers result to sender
    public fun swap_a_to_b_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        token_a: Coin<TokenA>,
        min_amount_out: u64,
        ctx: &mut TxContext,
    ) {
        // TODO: Call dex_core::swap_a_to_b
        // TODO: Transfer result to sender
    }

    /// Swaps B to A and transfers result to sender
    public fun swap_b_to_a_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        token_b: Coin<TokenB>,
        min_amount_out: u64,
        ctx: &mut TxContext,
    ) {
        // TODO: Call dex_core::swap_b_to_a
        // TODO: Transfer result to sender
    }

    /// Collects admin fees and transfers to sender
    public fun collect_fees_and_transfer<TokenA, TokenB>(
        pair: &mut TradingPair<TokenA, TokenB>,
        admin_cap: &AdminCap,
        ctx: &mut TxContext,
    ) {
        // TODO: Call dex_core::collect_fees
        // TODO: Transfer fees to sender
    }

    // ================================
    // Helper Functions
    // ================================

    /// Safely transfers a coin to recipient, destroying if zero
    fun safe_transfer<T>(coin: Coin<T>, recipient: address) {
        if (coin::value(&coin) > 0) {
            transfer::public_transfer(coin, recipient);
        } else {
            coin::destroy_zero(coin);
        }
    }


    // ================================
    // Test Utilities
    // ================================

    #[test_only]
    /// Creates test coins for development
    public fun create_test_coins<T>(
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        // TODO: Create test coins for unit testing
        coin::zero(ctx)
    }

    #[test_only]
    /// Mints tokens for testing purposes
    public fun mint_for_testing<T>(
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // TODO: Mint and transfer test tokens
    }
} 